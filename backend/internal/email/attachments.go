package email

import (
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"mime"
	"mime/multipart"
	"net/mail"
	"os"
	"path/filepath"
	"strings"
)

// extractAttachments 从 .eml 文件递归提取附件并保存到磁盘
func extractAttachments(emlPath, attachDir string, emailID int64) (int, []string) {
	f, err := os.Open(emlPath)
	if err != nil {
		return 0, []string{err.Error()}
	}
	defer f.Close()

	msg, err := mail.ReadMessage(f)
	if err != nil {
		return 0, []string{err.Error()}
	}

	mediaType, params, err := mime.ParseMediaType(msg.Header.Get("Content-Type"))
	if err != nil || !strings.HasPrefix(mediaType, "multipart/") {
		return 0, nil
	}

	boundary := params["boundary"]
	if boundary == "" {
		return 0, nil
	}

	if err := os.MkdirAll(attachDir, 0755); err != nil {
		return 0, []string{err.Error()}
	}

	mr := multipart.NewReader(msg.Body, boundary)
	saved, warns := walkMIMEParts(mr, attachDir, emailID)
	log.Printf("[email] 提取附件 #%d: %d 个", emailID, saved)
	return saved, warns
}

// walkMIMEParts 递归遍历 multipart 树，提取 attachment
func walkMIMEParts(mr *multipart.Reader, attachDir string, emailID int64) (int, []string) {
	var warns []string
	saved := 0

	for {
		p, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			warns = append(warns, fmt.Sprintf("读取 part 失败: %v", err))
			break
		}

		ct := p.Header.Get("Content-Type")
		disp := p.Header.Get("Content-Disposition")

		// 嵌套 multipart → 递归
		if strings.HasPrefix(ct, "multipart/") {
			_, params, e := mime.ParseMediaType(ct)
			if e == nil && params["boundary"] != "" {
				sub := multipart.NewReader(p, params["boundary"])
				n, w := walkMIMEParts(sub, attachDir, emailID)
				saved += n
				warns = append(warns, w...)
			}
			p.Close()
			continue
		}

		// 检测附件 (attachment 或 Content-Type 非 text)
		_, dispParams, _ := mime.ParseMediaType(disp)
		isAttach := strings.Contains(disp, "attachment") || strings.Contains(disp, "inline")

		if isAttach {
			filename := pickFilename(dispParams, ct)
			savePath := filepath.Join(attachDir, sanitizeFilename(filename))

			data, readErr := io.ReadAll(p)
			p.Close()
			if readErr != nil {
				warns = append(warns, fmt.Sprintf("%s: 读取失败 — %v", filename, readErr))
				continue
			}

			decoded := decodeTransport(data, p.Header.Get("Content-Transfer-Encoding"))

			if err := os.WriteFile(savePath, decoded, 0644); err != nil {
				warns = append(warns, fmt.Sprintf("%s: 保存失败 — %v", filename, err))
				continue
			}
			saved++
			log.Printf("[email] 附件 #%d: %s (%d bytes)", emailID, filename, len(decoded))
		} else {
			p.Close()
		}
	}
	return saved, warns
}

// pickFilename 从 Content-Disposition 或 Content-Type 中提取文件名
func pickFilename(dispParams map[string]string, contentType string) string {
	if fn := dispParams["filename"]; fn != "" {
		return decodeRFC2047(fn)
	}
	_, ctParams, _ := mime.ParseMediaType(contentType)
	if fn := ctParams["name"]; fn != "" {
		return decodeRFC2047(fn)
	}
	return "unnamed_attachment"
}

// sanitizeFilename 清理文件名，只保留安全字符
func sanitizeFilename(name string) string {
	if name == "" {
		return "unnamed_attachment"
	}
	clean := strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') || r == '.' || r == '_' || r == '-' {
			return r
		}
		return '_'
	}, name)
	if clean == "" || clean == "." {
		return "unnamed_attachment"
	}
	if len(clean) > 120 {
		ext := filepath.Ext(clean)
		clean = clean[:120-len(ext)] + ext
	}
	return clean
}

// decodeRFC2047 解码 =?charset?B?xxx?= 格式的文件名
func decodeRFC2047(s string) string {
	dec := &mime.WordDecoder{}
	d, err := dec.DecodeHeader(s)
	if err != nil {
		return s
	}
	return d
}

// decodeTransport 解码 Content-Transfer-Encoding
func decodeTransport(data []byte, enc string) []byte {
	switch strings.ToLower(enc) {
	case "base64":
		clean := strings.NewReplacer("\n", "", "\r", "", " ", "", "\t", "").Replace(string(data))
		dec, err := base64.RawStdEncoding.DecodeString(clean)
		if err != nil {
			// 尝试 Standard
			dec, err = base64.StdEncoding.DecodeString(clean)
			if err != nil {
				return data // 解码失败，返回原始数据
			}
		}
		return dec
	case "quoted-printable":
		return decodeQP(data)
	default:
		return data
	}
}

// decodeQP 简单 quoted-printable 解码
func decodeQP(data []byte) []byte {
	result := make([]byte, 0, len(data))
	for i := 0; i < len(data); i++ {
		if data[i] == '=' && i+1 < len(data) {
			if data[i+1] == '\r' || data[i+1] == '\n' {
				if i+2 < len(data) && data[i+1] == '\r' && data[i+2] == '\n' {
					i += 2
				} else {
					i++
				}
				continue
			}
			if i+2 < len(data) && isHex(data[i+1]) && isHex(data[i+2]) {
				result = append(result, hexVal(data[i+1])<<4|hexVal(data[i+2]))
				i += 2
				continue
			}
		}
		result = append(result, data[i])
	}
	return result
}

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')
}

func hexVal(c byte) byte {
	if c >= '0' && c <= '9' {
		return c - '0'
	}
	if c >= 'A' && c <= 'F' {
		return c - 'A' + 10
	}
	return c - 'a' + 10
}

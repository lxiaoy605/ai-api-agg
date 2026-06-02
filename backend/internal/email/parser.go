package email

import (
	"io"
	"log"
	"mime"
	"mime/multipart"
	"net/mail"
	"strings"
)

// ParsedEmail 解析后的邮件结构
type ParsedEmail struct {
	MessageID   string
	From        []string
	To          []string
	Subject     string
	BodyText    string
	BodyHTML    string
	AttachCount int
	RawEML      string
}

// ParseRawEML 解析原始 EML 文本，提取所有字段
func ParseRawEML(raw string) *ParsedEmail {
	msg, err := mail.ReadMessage(strings.NewReader(raw))
	if err != nil {
		log.Printf("[email] 解析 EML 失败: %v", err)
		return nil
	}

	e := &ParsedEmail{
		MessageID: cleanMessageID(msg.Header.Get("Message-ID")),
		From:      parseAddrList(msg.Header, "From"),
		To:        parseAddrList(msg.Header, "To"),
		Subject:   decodeMIMEHeader(msg.Header.Get("Subject")),
		RawEML:    raw,
	}

	mediaType, params, err := mime.ParseMediaType(msg.Header.Get("Content-Type"))
	if err != nil {
		// 无 Content-Type，直接读 body
		body, _ := io.ReadAll(msg.Body)
		e.BodyText = decodeBody(body, msg.Header.Get("Content-Transfer-Encoding"))
		return e
	}

	if strings.HasPrefix(mediaType, "multipart/") {
		boundary := params["boundary"]
		if boundary != "" {
			mr := multipart.NewReader(msg.Body, boundary)
			walkParts(mr, e, 0)
		}
	} else {
		body, _ := io.ReadAll(msg.Body)
		if strings.HasPrefix(mediaType, "text/html") {
			e.BodyHTML = decodeBody(body, msg.Header.Get("Content-Transfer-Encoding"))
		} else {
			e.BodyText = decodeBody(body, msg.Header.Get("Content-Transfer-Encoding"))
		}
	}

	return e
}

type partWalker struct{ depth int }

func walkParts(mr *multipart.Reader, e *ParsedEmail, depth int) {
	for {
		p, err := mr.NextPart()
		if err == io.EOF {
			return
		}
		if err != nil {
			log.Printf("[email] 读取 MIME part 失败: %v", err)
			return
		}

		ct := p.Header.Get("Content-Type")
		disp := p.Header.Get("Content-Disposition")

		// attachment
		if strings.Contains(disp, "attachment") {
			e.AttachCount++
			p.Close()
			continue
		}

		// 嵌套 multipart
		if strings.HasPrefix(ct, "multipart/") {
			_, params, err := mime.ParseMediaType(ct)
			if err == nil && params["boundary"] != "" {
				sub := multipart.NewReader(p, params["boundary"])
				walkParts(sub, e, depth+1)
			}
			p.Close()
			continue
		}

		// 文本部分（优先取 text/plain，其次 text/html）
		body, _ := io.ReadAll(p)
		p.Close()

		media, _, _ := mime.ParseMediaType(ct)
		enc := p.Header.Get("Content-Transfer-Encoding")
		decoded := decodeBody(body, enc)

		switch media {
		case "text/plain":
			if e.BodyText == "" {
				e.BodyText = decoded
			}
		case "text/html":
			if e.BodyHTML == "" {
				e.BodyHTML = decoded
			}
		}
	}
}

// parseAddrList 解析地址列表头
func parseAddrList(h mail.Header, key string) []string {
	addrs, err := h.AddressList(key)
	if err != nil {
		return []string{decodeMIMEHeader(h.Get(key))}
	}
	result := make([]string, len(addrs))
	for i, a := range addrs {
		result[i] = a.Address
	}
	return result
}

// cleanMessageID 去掉 Message-ID 的尖括号
func cleanMessageID(id string) string {
	id = strings.TrimSpace(id)
	id = strings.TrimPrefix(id, "<")
	id = strings.TrimSuffix(id, ">")
	return id
}

// decodeMIMEHeader 解码 RFC2047 编码的邮件头
func decodeMIMEHeader(s string) string {
	dec := &mime.WordDecoder{}
	d, err := dec.DecodeHeader(s)
	if err != nil {
		return s
	}
	return d
}

// decodeBody 根据 Content-Transfer-Encoding 解码正文
func decodeBody(body []byte, enc string) string {
	switch strings.ToLower(enc) {
	case "base64":
		return string(decodeTransport(body, "base64"))
	case "quoted-printable":
		return string(decodeQP(body))
	default:
		return string(body)
	}
}

// stripHTML 简单去除 HTML 标签
func stripHTML(html string) string {
	s := strings.ReplaceAll(html, "<br/>", "\n")
	s = strings.ReplaceAll(s, "<br />", "\n")
	s = strings.ReplaceAll(s, "<br", "\n<br")
	s = strings.ReplaceAll(s, "</div>", "\n")
	s = strings.ReplaceAll(s, "</p>", "\n")
	// 移除标签
	for {
		start := strings.Index(s, "<")
		if start == -1 {
			break
		}
		end := strings.Index(s[start:], ">")
		if end == -1 {
			break
		}
		s = s[:start] + s[start+end+1:]
	}
	// 解码实体
	s = strings.ReplaceAll(s, "&amp;", "&")
	s = strings.ReplaceAll(s, "&lt;", "<")
	s = strings.ReplaceAll(s, "&gt;", ">")
	s = strings.ReplaceAll(s, "&nbsp;", " ")
	s = strings.ReplaceAll(s, "&quot;", "\"")
	// 压缩空行
	for strings.Contains(s, "\n\n\n") {
		s = strings.ReplaceAll(s, "\n\n\n", "\n\n")
	}
	return strings.TrimSpace(s)
}

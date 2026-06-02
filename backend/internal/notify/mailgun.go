package notify

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// mailgunSend 通过 Mailgun HTTP API 发送回复
func mailgunSend(apiKey, domain, to, origSubj, origMsgID, body string) error {
	if !strings.HasPrefix(strings.ToLower(origSubj), "re:") {
		origSubj = "Re: " + origSubj
	}

	payload := map[string]string{
		"from":            fmt.Sprintf("AiFlowHub <noreply@%s>", domain),
		"to":              to,
		"subject":         origSubj,
		"text":            body,
		"h:In-Reply-To": origMsgID,
		"h:References":    origMsgID,
	}

	b, _ := json.Marshal(payload)
	url := fmt.Sprintf("https://api.eu.mailgun.net/v3/%s/messages", domain)
	req, _ := http.NewRequest("POST", url, bytes.NewReader(b))
	req.SetBasicAuth("api", apiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		errBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("Mailgun 返回 %d: %s", resp.StatusCode, string(errBody))
	}
	return nil
}

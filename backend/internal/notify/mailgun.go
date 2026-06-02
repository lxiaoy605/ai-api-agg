package notify

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// mailgunSend 通过 Mailgun HTTP API 发送回复
func mailgunSend(apiKey, domain, to, origSubj, origMsgID, body string) error {
	if !strings.HasPrefix(strings.ToLower(origSubj), "re:") {
		origSubj = "Re: " + origSubj
	}

	form := url.Values{}
	form.Set("from", fmt.Sprintf("AiFlowHub <noreply@%s>", domain))
	form.Set("to", to)
	form.Set("subject", origSubj)
	form.Set("text", body)
	form.Set("h:In-Reply-To", origMsgID)
	form.Set("h:References", origMsgID)

	apiURL := fmt.Sprintf("https://api.eu.mailgun.net/v3/%s/messages", domain)
	req, _ := http.NewRequest("POST", apiURL, strings.NewReader(form.Encode()))
	req.SetBasicAuth("api", apiKey)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

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

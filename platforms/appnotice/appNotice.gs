//####################################################################################################################################################
//# ファイル   : appNotice.gs
//#
//#---------------------------------------------------------------------------------------------------------------------------------------------------
//# 【修正履歴】
//# V-001      : 2026/06/27                 Gamer-Iris   新規作成
//#
//####################################################################################################################################################

function hook() {
  console.log("[hook] 開始");

  // Gmail検索
  let threads;
  try {
    const query = "subject:TrueNAS is:unread";
    threads = GmailApp.search(query);
  } catch (e) {
    console.error("[hook] Gmail検索エラー: " + e.message);
    return;
  }

  if (threads.length === 0) {
    console.log("[hook] 新規メッセージなし - 終了");
    return;
  }
  console.log("[hook] 対象スレッド数: " + threads.length);

  // Webhook URL取得（ループ外で1回のみ）
  let noticeInfo;
  try {
    noticeInfo = appNoticeInfo();
  } catch (e) {
    console.error("[hook] appNoticeInfo取得エラー: " + e.message);
    return;
  }

  const webhookUrl = noticeInfo[0];
  if (!webhookUrl || webhookUrl === "ご自分の環境に合わせてください。") {
    console.error("[hook] Discord Webhook URLが未設定です - 終了");
    return;
  }

  // スレッドごとに通知・削除
  threads.forEach(function (thread) {
    try {
      const threadId = thread.getId();
      console.log("[hook] スレッド処理開始: " + threadId);

      const messages = thread.getMessages();
      let allSuccess = true;

      for (let i = 0; i < messages.length; i++) {
        const message = messages[i];

        const from = message.getFrom();
        const subject = message.getSubject();
        const plainBody = message.getPlainBody();
        console.log(
          "[hook] メッセージ送信 (" +
            (i + 1) +
            "/" +
            messages.length +
            "): " +
            subject,
        );

        const payload = {
          content: subject,
          embeds: [
            {
              title: subject,
              author: { name: from },
              description: plainBody.substring(0, 1900),
            },
          ],
        };

        const success = sendDiscordWebhook(webhookUrl, payload);
        if (!success) {
          allSuccess = false;
          console.error(
            "[hook] メッセージ送信失敗 - このスレッドのゴミ箱移動をスキップ: " +
              threadId,
          );
        }

        // 連続送信による429を避けるため次のメッセージ前に待機
        if (i < messages.length - 1) {
          Utilities.sleep(1500);
        }
      }

      // 全件送信成功した場合のみ既読化・ゴミ箱へ移動
      if (allSuccess) {
        console.log("[hook] 全件送信成功 - 既読化実施: " + threadId);
        thread.markRead();
        console.log("[hook] スレッドをゴミ箱へ移動: " + threadId);
        thread.moveToTrash();
      } else {
        console.log(
          "[hook] 送信失敗あり - 未読維持・ゴミ箱移動せず（次回トリガーで再試行）: " +
            threadId,
        );
      }

      console.log("[hook] スレッド処理完了: " + threadId);
    } catch (e) {
      console.error(
        "[hook] スレッド処理エラー [" + thread.getId() + "]: " + e.message,
      );
    }
  });

  console.log("[hook] 終了");
}

function sendDiscordWebhook(webhookUrl, payload) {
  const MAX_RETRIES = 3;
  const DEFAULT_SLEEP_MS = 2000;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    let response;
    try {
      response = UrlFetchApp.fetch(webhookUrl, {
        method: "post",
        contentType: "application/json",
        payload: JSON.stringify(payload),
        muteHttpExceptions: true,
      });
    } catch (e) {
      console.error(
        "[sendDiscordWebhook] UrlFetchApp例外 (試行" +
          attempt +
          "/" +
          MAX_RETRIES +
          "): " +
          e.message,
      );
      if (attempt < MAX_RETRIES) Utilities.sleep(DEFAULT_SLEEP_MS);
      continue;
    }

    const code = response.getResponseCode();
    const body = response.getContentText();
    console.log(
      "[sendDiscordWebhook] responseCode=" +
        code +
        " body=" +
        body.substring(0, 300),
    );

    if (code === 200 || code === 204) {
      return true;
    }

    if (code === 429) {
      // retry_after を Discord レスポンスから取得（単位: 秒）
      let waitMs = DEFAULT_SLEEP_MS;
      try {
        const json = JSON.parse(body);
        if (json.retry_after) {
          waitMs = Math.ceil(json.retry_after * 1000) + 500;
        }
      } catch (_) {}
      console.log(
        "[sendDiscordWebhook] 429 Rate Limit - " +
          waitMs +
          "ms 待機 (試行" +
          attempt +
          "/" +
          MAX_RETRIES +
          ")",
      );
      if (attempt < MAX_RETRIES) Utilities.sleep(waitMs);
      continue;
    }

    if (code >= 500) {
      console.log(
        "[sendDiscordWebhook] 5xx エラー - " +
          DEFAULT_SLEEP_MS +
          "ms 待機 (試行" +
          attempt +
          "/" +
          MAX_RETRIES +
          ")",
      );
      if (attempt < MAX_RETRIES) Utilities.sleep(DEFAULT_SLEEP_MS);
      continue;
    }

    // 4xx (429以外) はリトライしない
    console.error(
      "[sendDiscordWebhook] 4xx エラー (code=" +
        code +
        ") - リトライ不可・失敗",
    );
    return false;
  }

  console.error(
    "[sendDiscordWebhook] 最大リトライ回数(" + MAX_RETRIES + ")到達 - 失敗",
  );
  return false;
}

function appNoticeInfo() {
  //シートURLで取得して変数「ss」に格納
  const ss = SpreadsheetApp.openByUrl("ご自分の環境に合わせてください。");

  //取得したシートIDのシート名「appNotice」で取得して変数「sheet」に格納
  const sheet = ss.getSheetByName("appNotice");

  //各項目の取得
  const discord_url = sheet.getRange("C2").getValue();
  return [discord_url];
}

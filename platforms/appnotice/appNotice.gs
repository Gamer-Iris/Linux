//####################################################################################################################################################
//# ファイル   : appNotice.gs
//#
//#---------------------------------------------------------------------------------------------------------------------------------------------------
//# 【修正履歴】
//# V-001      : 2026/01/01                 Gamer-Iris   新規作成
//#
//####################################################################################################################################################

function hook() {
  const query = "subject:TrueNAS is:unread";
  const threads = GmailApp.search(query);

  if (threads.length == 0) {
    Logger.log("新規メッセージなし");
    return;
  }

  threads.forEach(function (thread) {
    const messages = thread.getMessages();
    payloads = messages.map(function (message) {
      //メールを既読に設定
      message.markRead();

      //通知準備
      from = message.getFrom();
      subject = message.getSubject();
      plainBody = message.getPlainBody();
      appNoticeInfo = appNoticeInfo();
      Logger.log(subject);
      payload = {
        content: subject,
        embeds: [
          {
            title: subject,
            author: {
              name: from,
            },
            description: plainBody.substring(0, 2048),
          },
        ],
      };
      return {
        url: appNoticeInfo[0],
        contentType: "application/json",
        payload: JSON.stringify(payload),
      };
    });

    //通知実施
    Logger.log(payloads);
    UrlFetchApp.fetchAll(payloads);

    //メール削除
    for (var i = 0; i < threads.length; i++) {
      threads[i].moveToTrash();
      Gmail.Users.Messages.remove("me", threads[i].getId());
    }
  });
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

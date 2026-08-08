// The corpus. Thirty chat screens the keyboard has to read.
//
// Each scene is the single source of truth for one screenshot: skins.mjs turns
// it into pixels, generate.mjs measures the ground truth back off those pixels.
// `expected` is derived (last incoming text message) unless a scene overrides
// it, because the hard cases are exactly the ones where the obvious derivation
// is wrong.
//
// Message fields
//   from        "them" | "me"
//   sender      who wrote it, for attribution
//   senderLabel name drawn above/beside the bubble (groups, Slack, mail)
//   kind        text (default) | date | system | unread | voice | image
//   status      WhatsApp/Telegram: "sent" | "read" (ticks)
//               Messages: the literal receipt string ("Delivered", "נקרא 8:36")
//   quoted      { name, text }  reply-to block: chrome, not the message
//   forwarded   "Forwarded from X": chrome
//   card        link preview: chrome, even though it reads like a sentence
//   reactions   ["❤️ 2"]: chrome
//
// Scene fields
//   expectedOverride  { message?, sender?, none?, reason?, truncatedAtTop? }
//   traps             text on screen a naive reader would return instead

export const scenes = [
  // -------------------------------------------------------------- WhatsApp
  {
    id: "wa-01",
    app: "WhatsApp",
    appearance: "light",
    language: "hebrew",
    dir: "rtl",
    statusTime: "9:41",
    hardCases: ["system-message", "sender-name-is-a-phrase", "time-inside-message"],
    notes:
      "Encryption notice sits above the thread in its own bubble and reads like a message. " +
      "The contact is saved as 'שרה כהן - עבודה', which is a phrase, not a first name. " +
      "The message body contains '10:30', which looks exactly like the bubble timestamps.",
    header: { title: "שרה כהן - עבודה", subtitle: "מקוונת" },
    messages: [
      {
        kind: "system",
        text: "ההודעות והשיחות מוצפנות מקצה לקצה. לאף אחד מחוץ לצ'אט הזה, גם לא ל-WhatsApp, אין אפשרות לקרוא אותן.",
      },
      { kind: "date", text: "היום" },
      { from: "them", sender: "שרה כהן - עבודה", text: "היי, איך היה בכנס אתמול?", time: "8:41" },
      { from: "me", sender: "אני", text: "מעניין. פגשתי שם את דניאל מהחברה ההיא", time: "8:47", status: "read" },
      { from: "them", sender: "שרה כהן - עבודה", text: "מעולה. הוא עדיין מחפש ספקים?", time: "8:49" },
      { from: "me", sender: "אני", text: "כן, אמרתי לו שנשלח לו משהו השבוע", time: "8:52", status: "read" },
      { from: "them", sender: "שרה כהן - עבודה", text: "יופי, אני אכין טיוטה היום", time: "8:55" },
      { from: "them", sender: "שרה כהן - עבודה", text: "בוקר טוב! ראית את המייל מרונן?", time: "9:12" },
      { from: "me", sender: "אני", text: "כן, עניתי לו אתמול בלילה", time: "9:14", status: "read" },
      {
        from: "them",
        sender: "שרה כהן - עבודה",
        text: "מעולה. אז אנחנו סוגרים על פגישה ביום שלישי ב-10:30 במשרד?",
        time: "9:15",
      },
    ],
    traps: [
      { text: "ההודעות והשיחות מוצפנות מקצה לקצה", why: "app boilerplate rendered as a bubble" },
      { text: "9:15", why: "bubble timestamp, one pixel row under the message text" },
      { text: "10:30", why: "a time inside the message body; stripping all times would corrupt the message" },
    ],
  },
  {
    id: "wa-02",
    app: "WhatsApp",
    appearance: "dark",
    language: "hebrew",
    dir: "ltr",
    statusTime: "20:44",
    hardCases: ["reactions", "emoji-in-message", "typing-indicator", "hebrew-in-ltr-layout"],
    notes:
      "The phone's UI language is English but the conversation is Hebrew, which is how most " +
      "Israeli users actually run their device. The app chrome stays left-to-right, incoming " +
      "bubbles stay on the left, and only the message text is right-aligned. Reaction pills " +
      "overlap the bubble edge, so the count sits on the same line as the last words.",
    header: { title: "מאיה", subtitle: "מקלידה…" },
    messages: [
      { kind: "date", text: "היום" },
      { from: "them", sender: "מאיה", text: "נחתת?", time: "18:40" },
      { from: "me", sender: "אני", text: "נחתנו, מחכה למזוודה", time: "19:20", status: "read" },
      { from: "them", sender: "מאיה", text: "סעי בזהירות, יורד גשם", time: "19:26" },
      { from: "me", sender: "אני", text: "חזרתי! הטיסה איחרה בשעתיים", time: "19:58", status: "read" },
      { from: "them", sender: "מאיה", text: "וואי, נשמע מתיש. הספקת לישון?", time: "20:14" },
      { from: "me", sender: "אני", text: "קצת. אני הולך לישון מוקדם היום", time: "20:20", status: "read" },
      { from: "them", sender: "מאיה", text: "מגיע לך. תשלח תמונות כשתתעורר", time: "20:31" },
      { from: "me", sender: "אני", text: "העליתי עכשיו לאלבום המשותף", time: "20:38", status: "read" },
      {
        from: "them",
        sender: "מאיה",
        text: "וואו הצילומים מהטיול יצאו מדהים 😍",
        time: "20:41",
        reactions: ["❤️"],
      },
      { from: "me", sender: "אני", text: "נכון?! שלחתי לך את כולם בדרייב", time: "20:43", status: "read" },
      {
        from: "them",
        sender: "מאיה",
        text: "תודה!! 🙏 אני אעלה כמה לאינסטגרם מחר בבוקר, בסדר מבחינתך?",
        time: "20:44",
        reactions: ["👍 2"],
      },
    ],
    traps: [
      { text: "👍 2", why: "reaction pill; the '2' is a count, not text" },
      { text: "מקלידה…", why: "presence string in the nav bar" },
    ],
  },
  {
    id: "wa-03",
    app: "WhatsApp",
    appearance: "light",
    language: "mixed",
    dir: "rtl",
    statusTime: "11:09",
    hardCases: ["group-chat", "sender-name-above-text", "hebrew-with-english-words"],
    notes:
      "Group chat: each incoming bubble carries a coloured sender name directly above the body, " +
      "with no blank line between them. The last message mixes Hebrew with 'bug', 'onboarding', " +
      "'fix' and 'release'.",
    header: { title: "צוות מוצר 🚀", subtitle: "אתה, דניאל, נועה, איתי" },
    messages: [
      { kind: "date", text: "היום" },
      {
        from: "them",
        sender: "איתי ברק",
        senderLabel: "איתי ברק",
        text: "בוקר טוב, מתחילים את הספרינט היום?",
        time: "9:14",
      },
      { from: "me", sender: "אני", text: "כן, אחרי הסטנדאפ", time: "9:20", status: "read" },
      {
        from: "them",
        sender: "נועה לוי",
        senderLabel: "נועה לוי",
        text: "אני עדיין מחכה לאישור מהעיצוב על המסך האחרון",
        time: "9:41",
      },
      {
        from: "them",
        sender: "דניאל כהן",
        senderLabel: "דניאל כהן",
        text: "אישרתי אתמול בערב, תבדקי בפיגמה",
        time: "10:03",
      },
      {
        from: "them",
        sender: "נועה לוי",
        senderLabel: "נועה לוי",
        text: "מצוין, ראיתי. מתחילה לבנות",
        time: "10:11",
      },
      {
        from: "them",
        sender: "נועה לוי",
        senderLabel: "נועה לוי",
        text: "העליתי את ה-build החדש ל-TestFlight, מספר 142",
        time: "11:02",
      },
      { from: "them", sender: "איתי ברק", senderLabel: "איתי ברק", text: "אני בודק עכשיו", time: "11:04" },
      { from: "me", sender: "אני", text: "מעולה, תעדכנו", time: "11:05", status: "read" },
      {
        from: "them",
        sender: "דניאל כהן",
        senderLabel: "דניאל כהן",
        text: "יש bug ב-onboarding, המסך השני נתקע כשבוחרים עברית. אפשר fix לפני ה-release מחר?",
        time: "11:09",
      },
    ],
    traps: [
      { text: "דניאל כהן", why: "sender label butts against the first word of the message" },
      { text: "צוות מוצר 🚀", why: "group name in the nav bar" },
      { text: "אתה, דניאל, נועה, איתי", why: "participant list reads like a sentence fragment" },
    ],
  },
  {
    id: "wa-04",
    app: "WhatsApp",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "9:03",
    hardCases: ["scrolled-off-top"],
    notes:
      "A long recap message from earlier in the day is cut by the top of the thread view. Its " +
      "first lines are simply not on screen, and a correct reader must not invent them.",
    header: { title: "James Whitfield", subtitle: "last seen today at 8:58" },
    messages: [
      { kind: "date", text: "TODAY" },
      { from: "them", sender: "James Whitfield", text: "Are you up?", time: "8:35" },
      { from: "me", sender: "Me", text: "Barely. Coffee first.", time: "8:36", status: "read" },
      { from: "them", sender: "James Whitfield", text: "Fair. Take five minutes, this one is long.", time: "8:37" },
      { from: "me", sender: "Me", text: "Go ahead, I'm reading.", time: "8:40", status: "read" },
      { from: "them", sender: "James Whitfield", text: "Right, here it is.", time: "8:40" },
      {
        from: "them",
        sender: "James Whitfield",
        text:
          "Morning, quick recap from the call with the vendor yesterday so it is written down somewhere: " +
          "they can hold the current pricing until the end of the quarter, but only if we commit to the " +
          "two year term. If we go month to month the rate goes up by about eighteen percent starting in " +
          "October, and they will not budge on the setup fee. I told them we would come back by Thursday.",
        time: "8:41",
      },
      {
        from: "me",
        sender: "Me",
        text: "Thanks for writing it up. Two years is a lot to commit to.",
        time: "8:52",
        status: "read",
      },
      {
        from: "them",
        sender: "James Whitfield",
        text: "Also the legal review came back clean, so nothing blocking on that side.",
        time: "8:55",
      },
      { from: "me", sender: "Me", text: "Good. I will look at the numbers tonight.", time: "8:58", status: "read" },
      {
        from: "them",
        sender: "James Whitfield",
        text: "Can you sanity check the numbers before I reply to them on Thursday?",
        time: "9:03",
      },
    ],
    traps: [
      { text: "last seen today at 8:58", why: "presence line that looks like content" },
      { text: "TODAY", why: "date chip; may or may not still be on screen" },
    ],
  },
  {
    id: "wa-05",
    app: "WhatsApp",
    appearance: "light",
    language: "hebrew",
    dir: "rtl",
    statusTime: "16:22",
    hardCases: ["last-message-is-outgoing"],
    notes:
      "The two newest bubbles are the user's own. The thing worth replying to is three bubbles up. " +
      "A reader that grabs the bottom-most bubble replies to the user's own words.",
    header: { title: "אבא", subtitle: "נראה לאחרונה היום ב-16:20" },
    messages: [
      { kind: "date", text: "היום" },
      { from: "them", sender: "אבא", text: "בוקר טוב, לקחתי את האוטו למוסך", time: "9:05" },
      { from: "me", sender: "אני", text: "תודה רבה! אמרו כמה זמן?", time: "9:40", status: "read" },
      { from: "them", sender: "אבא", text: "אמרו עד אחר הצהריים", time: "9:44" },
      { from: "them", sender: "אבא", text: "שלום, סידרתי את העניין עם המוסך", time: "15:40" },
      { from: "me", sender: "אני", text: "תודה! כמה יצא בסוף?", time: "15:52", status: "read" },
      { from: "them", sender: "אבא", text: "1,240 כולל הבלמים. הם נתנו הנחה", time: "15:55" },
      { from: "me", sender: "אני", text: "מעולה, אני אעביר לך הערב", time: "16:01", status: "read" },
      { from: "them", sender: "אבא", text: "אין לחץ", time: "16:03" },
      { from: "them", sender: "אבא", text: "אתה מגיע לארוחת ערב בשישי? אמא שואלת", time: "16:20" },
      { from: "me", sender: "אני", text: "כן, נגיע בסביבות שבע", time: "16:22", status: "read" },
      { from: "me", sender: "אני", text: "אני מביא יין", time: "16:22", status: "sent" },
    ],
    expectedOverride: {
      lastMessageIsOutgoing: true,
      reason: "The last two bubbles are outgoing. The newest incoming message is the one above them.",
    },
    traps: [{ text: "אני מביא יין", why: "bottom-most bubble, but it is the user's own message" }],
  },
  {
    id: "wa-06",
    app: "WhatsApp",
    appearance: "dark",
    language: "hebrew",
    dir: "rtl",
    statusTime: "18:02",
    keyboard: { lang: "he" },
    hardCases: ["keyboard-up", "scrolled-off-top", "message-truncated-at-top"],
    notes:
      "The Hebrew keyboard takes the bottom third, so the thread is short and the long building " +
      "notice is cut through its own middle. Only the tail of the message is readable. Forty-odd " +
      "single Hebrew letters from the key caps are the densest chrome on any screen in the corpus.",
    header: { title: "רותם - ועד הבית", subtitle: "מקוונת" },
    messages: [
      { kind: "date", text: "היום" },
      { from: "them", sender: "רותם - ועד הבית", text: "ערב טוב, שלחתי הודעה גם בקבוצה", time: "18:00" },
      {
        from: "them",
        sender: "רותם - ועד הבית",
        text:
          "שלום לכולם, רציתי לעדכן שהוועד החליט לבצע שיפוץ בלובי ובחדר המדרגות בחודש הבא. " +
          "העבודות יתחילו ביום שלישי ה-3 בספטמבר ויימשכו כשלושה שבועות, אולי קצת יותר אם יתגלו " +
          "בעיות רטיבות בקיר המערבי כמו שקרה בבניין הסמוך בשנה שעברה. בזמן העבודות המעלית תהיה " +
          "מושבתת בכל יום בין 8:00 ל-16:00, אז מי שצריך להוריד או להעלות דברים כבדים מתבקש לעשות " +
          "את זה בשעות הערב או בסופי שבוע. גם הכניסה הראשית תיחסם לסירוגין, ובימים האלה ניכנס " +
          "דרך החניון התחתון. בנוסף, צריך לאסוף 450 שקל מכל דירה עד סוף החודש כדי לשלם לקבלן " +
          "את המקדמה. אפשר להעביר לי בביט או במזומן לתיבת הדואר בקומת הכניסה. מי שמשלם במזומן " +
          "שירשום את מספר הדירה על המעטפה. תעדכנו אותי בהקדם אם יש בעיה עם התאריכים או עם הסכום, " +
          "ואם מישהו רוצה להצטרף לוועד השיפוץ שיכתוב לי בפרטי.",
        time: "18:02",
      },
    ],
    expectedOverride: {
      truncatedAtTop: true,
      reason:
        "The newest incoming message is taller than the visible thread, so its opening lines are " +
        "off screen. The correct answer is the visible tail, not the full message.",
    },
    traps: [
      { text: "קראטוןםפ שדגכעיחלךף זסבהנמצתץ", why: "keyboard key caps: 27 single Hebrew letters" },
      { text: "אני תודה בסדר", why: "iOS predictive-text suggestions above the keys" },
      { text: "רווח", why: "space bar label" },
    ],
  },
  {
    id: "wa-07",
    app: "WhatsApp",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "13:53",
    hardCases: ["no-repliable-text", "voice-note"],
    notes:
      "The newest incoming message is a voice note. There is no text to reply to. The previous " +
      "incoming line was already answered by the user, so returning it would be stale.",
    header: { title: "Priya Raman", subtitle: "online" },
    messages: [
      { kind: "date", text: "TODAY" },
      { from: "them", sender: "Priya Raman", text: "morning, is the cluster still on the old instance type?", time: "9:12" },
      { from: "me", sender: "Me", text: "yes, migration is scheduled for next sprint", time: "9:30", status: "read" },
      { from: "them", sender: "Priya Raman", text: "ok, that's what I assumed", time: "9:31" },
      { from: "them", sender: "Priya Raman", text: "did the storage numbers ever come back from finance?", time: "11:20" },
      { from: "me", sender: "Me", text: "not yet, chasing them", time: "11:44", status: "read" },
      { from: "them", sender: "Priya Raman", text: "ok. I need them before I can size the cluster", time: "11:46" },
      { from: "me", sender: "Me", text: "understood, I'll push today", time: "12:02", status: "read" },
      { from: "them", sender: "Priya Raman", text: "hey are you around?", time: "13:40" },
      { from: "me", sender: "Me", text: "just got out of a meeting, what's up", time: "13:52", status: "read" },
      { from: "them", sender: "Priya Raman", kind: "voice", text: "", duration: "0:47", time: "13:53" },
    ],
    expectedOverride: {
      none: true,
      reason:
        "Newest incoming message carries no text. Correct behaviour is to report nothing repliable, " +
        "not to fall back to the older answered line.",
      staleIncomingText: "hey are you around?",
    },
    traps: [
      { text: "0:47", why: "voice-note duration, the only text in that bubble" },
      { text: "hey are you around?", why: "older incoming text the user already answered" },
    ],
  },
  {
    id: "wa-08",
    app: "WhatsApp",
    appearance: "dark",
    language: "mixed",
    dir: "rtl",
    statusTime: "15:22",
    hardCases: ["reply-quote", "hebrew-with-english-words"],
    notes:
      "The newest bubble contains a quoted copy of the user's own earlier message stacked directly " +
      "above the actual reply, inside the same bubble.",
    header: { title: "תומר בר-און", subtitle: "מקוון" },
    messages: [
      { kind: "date", text: "היום" },
      { from: "them", sender: "תומר בר-און", text: "בוקר טוב, סיימתי לקרוא את ה-RFC", time: "10:12" },
      { from: "me", sender: "אני", text: "ומה דעתך?", time: "10:40", status: "read" },
      { from: "them", sender: "תומר בר-און", text: "בגדול מסכים. יש כמה דברים שכדאי לחדד", time: "10:47" },
      { from: "me", sender: "אני", text: "אשמח לשמוע", time: "11:02", status: "read" },
      { from: "them", sender: "תומר בר-און", text: "היי, יש לך דקה אחר כך?", time: "14:30" },
      { from: "me", sender: "אני", text: "כן, אחרי 3 אני פנוי", time: "14:38", status: "read" },
      { from: "them", sender: "תומר בר-און", text: "מעולה. רוצה לעבור על ה-architecture לפני שאנחנו מתחילים", time: "14:41" },
      { from: "me", sender: "אני", text: "בדיוק על זה חשבתי", time: "14:52", status: "read" },
      {
        from: "me",
        sender: "אני",
        text: "העליתי את ה-spec ל-Notion, יש שם 3 open questions",
        time: "15:10",
        status: "read",
      },
      {
        from: "them",
        sender: "תומר בר-און",
        quoted: { name: "אתה", text: "העליתי את ה-spec ל-Notion, יש שם 3 open questions" },
        text: "קראתי. על שאלה 2 אני חושב שכדאי ללכת על server-side, זה יחסוך לנו את כל ה-sync logic",
        time: "15:22",
      },
    ],
    traps: [
      {
        text: "העליתי את ה-spec ל-Notion, יש שם 3 open questions",
        why: "quote block inside the newest bubble; it is the user's own older message",
      },
      { text: "אתה", why: "quote attribution label" },
    ],
  },

  // ----------------------------------------------------------------- Slack
  {
    id: "sl-01",
    app: "Slack",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "10:24",
    hardCases: ["sender-name-and-timestamp-inline", "channel-chrome"],
    notes:
      "Slack has no bubbles. Sender name and timestamp share a line with no separator from the " +
      "message body below, which is the classic OCR run-on: 'Daniel Cohen 10:24 AM Can you take…'.",
    header: { title: "# product-eng", subtitle: "128 members" },
    composer: "Message #product-eng",
    messages: [
      { kind: "date", text: "Today" },
      { from: "them", sender: "Ana Delgado", text: "Anyone still merging into main this morning?", time: "9:04 AM" },
      { from: "them", sender: "Yosef Aviram", text: "Not me, I'm done for now.", time: "9:11 AM" },
      { from: "me", sender: "You", text: "Same, go ahead.", time: "9:19 AM" },
      {
        from: "them",
        sender: "Ana Delgado",
        text: "Starting the staging deploy now, should be about ten minutes.",
        time: "9:28 AM",
      },
      { from: "them", sender: "Yosef Aviram", text: "Thanks. I'll hold off on merging until it's green.", time: "9:33 AM" },
      {
        from: "them",
        sender: "Ana Delgado",
        text: "Deploy to staging finished, build 4471 is up.",
        time: "9:41 AM",
      },
      { from: "them", sender: "Ana Delgado", cont: true, text: "No errors in the last 20 minutes." },
      { from: "me", sender: "You", text: "Nice. I'll run the smoke tests after lunch.", time: "9:58 AM" },
      {
        from: "them",
        sender: "Daniel Cohen",
        text: "Can you take the standup tomorrow? I have a conflict at 9.",
        time: "10:24 AM",
      },
    ],
    traps: [
      { text: "Daniel Cohen 10:24 AM", why: "name and time on the line immediately above the message" },
      { text: "# product-eng", why: "channel name in the nav bar" },
      { text: "128 members", why: "member count under the channel name" },
    ],
  },
  {
    id: "sl-02",
    app: "Slack",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "11:31",
    hardCases: ["reactions", "thread-reply-count"],
    notes:
      "Reaction pills and a thread reply-count line sit between two messages. '4 replies Last reply " +
      "12 minutes ago' is a full English sentence that belongs to nobody.",
    header: { title: "Marcus Reeve", subtitle: "Active" },
    composer: "Message Marcus Reeve",
    messages: [
      { kind: "date", text: "Today" },
      { from: "them", sender: "Marcus Reeve", text: "Morning. Did you get anywhere with the auth bug?", time: "10:31 AM" },
      { from: "me", sender: "You", text: "Reproduced it. It only happens after the token expires mid-session.", time: "10:44 AM" },
      { from: "them", sender: "Marcus Reeve", text: "That narrows it a lot. Give me twenty minutes.", time: "10:47 AM" },
      {
        from: "them",
        sender: "Marcus Reeve",
        text:
          "Pushed the fix for the token refresh loop. Turned out we were retrying on 401 without " +
          "clearing the cached credential.",
        time: "11:02 AM",
        reactions: ["🎉 3", "🙌 1"],
        replies: "4 replies   Last reply 12 minutes ago",
      },
      {
        from: "me",
        sender: "You",
        text: "Beautiful. Does that also explain the logout spikes on Android?",
        time: "11:20 AM",
      },
      {
        from: "them",
        sender: "Marcus Reeve",
        text: "Almost certainly. Can you check the Sentry numbers after the release goes out at 2?",
        time: "11:31 AM",
      },
    ],
    traps: [
      { text: "4 replies   Last reply 12 minutes ago", why: "thread affordance, reads as a sentence" },
      { text: "🎉 3", why: "reaction pill with a count" },
      { text: "Active", why: "presence string" },
    ],
  },
  {
    id: "sl-03",
    app: "Slack",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "8:05",
    hardCases: ["scrolled-off-top", "bot-message"],
    notes:
      "An incident channel. The bot post and the long 3am writeup are cut by the top edge. The " +
      "App badge next to the bot name is chrome that OCR reads as the word 'App'.",
    header: { title: "# incidents", subtitle: "42 members" },
    composer: "Message #incidents",
    messages: [
      { kind: "date", text: "Today" },
      {
        from: "them",
        sender: "Ops Bot",
        appTag: true,
        text: "INC-2291 opened: elevated 5xx on api-gateway (eu-west-1). Auto-paged the on-call.",
        time: "3:02 AM",
      },
      { from: "them", sender: "Priya Raman", text: "I'm on it. Looking at the gateway dashboards now.", time: "3:06 AM" },
      { from: "them", sender: "Priya Raman", cont: true, text: "Error rate is sitting around eleven percent." },
      { from: "them", sender: "Tom Aldridge", text: "Anything you need from me, or are you good?", time: "3:09 AM" },
      { from: "them", sender: "Priya Raman", text: "Good for now. Go back to sleep, I'll write it up.", time: "3:11 AM" },
      { from: "them", sender: "Tom Aldridge", text: "Thanks. Ping me if it turns into a page.", time: "3:12 AM" },
      {
        from: "them",
        sender: "Priya Raman",
        text:
          "Root cause is the connection pool on the read replica. We raised max connections last " +
          "week for the migration and never put it back, so the gateway was opening more sockets " +
          "than the replica would accept and failing closed instead of queueing. Rolled the config " +
          "back at 3:41 and error rate was under one percent within four minutes. Nothing was lost, " +
          "but roughly nine thousand requests got a 502 during the window.",
        time: "3:14 AM",
      },
      { from: "me", sender: "You", text: "Thanks for handling it overnight. Anything still open?", time: "7:40 AM" },
      {
        from: "them",
        sender: "Priya Raman",
        text: "Wrote the postmortem draft. Can you add the customer impact section before the review at 4?",
        time: "8:05 AM",
      },
    ],
    traps: [
      { text: "App", why: "bot badge next to the sender name" },
      { text: "INC-2291 opened: elevated 5xx on api-gateway (eu-west-1).", why: "automated post, not a person" },
    ],
  },
  {
    id: "sl-04",
    app: "Slack",
    appearance: "dark",
    language: "mixed",
    dir: "ltr",
    statusTime: "10:52",
    hardCases: ["link-preview", "hebrew-in-ltr-layout", "hebrew-with-english-words"],
    notes:
      "Hebrew messages inside a left-to-right Slack layout: the paragraph is right-aligned while " +
      "the sender name, avatar and timestamp stay on the left. The link preview underneath the " +
      "first message is a Hebrew sentence that is not a message.",
    header: { title: "# israel-launch", subtitle: "17 members" },
    composer: "Message #israel-launch",
    messages: [
      { kind: "date", text: "Today" },
      { from: "them", sender: "Adi Peretz", text: "Reminder: Hebrew launch is a week from Thursday.", time: "9:02 AM" },
      { from: "them", sender: "נועה לוי", text: "התרגומים מוכנים, נשאר רק העמוד הראשי", time: "9:26 AM" },
      { from: "me", sender: "You", text: "Who is reviewing the legal copy?", time: "9:48 AM" },
      { from: "them", sender: "Adi Peretz", text: "Legal signed off yesterday. We're clear.", time: "9:55 AM" },
      {
        from: "them",
        sender: "נועה לוי",
        text: "עמוד הנחיתה בעברית עלה, אשמח לעיניים לפני שאנחנו מפרסמים",
        time: "10:15 AM",
        card: {
          title: "AIKeyboard - מקלדת עברית חכמה",
          desc: "תרגום, ניסוח מחדש והכתבה, ישירות מהמקלדת. בלי להעתיק ובלי לעבור אפליקציה.",
          host: "aikeyboard.app",
        },
      },
      {
        from: "me",
        sender: "You",
        text: "Looks good. RTL punctuation on the pricing table is off though.",
        time: "10:40 AM",
      },
      {
        from: "them",
        sender: "נועה לוי",
        text: "תיקנתי את ה-RTL בטבלה, אפשר לעשות review לפני שאני מעלה ל-production?",
        time: "10:52 AM",
      },
    ],
    traps: [
      {
        text: "תרגום, ניסוח מחדש והכתבה, ישירות מהמקלדת. בלי להעתיק ובלי לעבור אפליקציה.",
        why: "link preview description; a complete Hebrew sentence that nobody wrote in the chat",
      },
      { text: "aikeyboard.app", why: "link preview host" },
    ],
  },
  {
    id: "sl-05",
    app: "Slack",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "2:13",
    keyboard: { lang: "en", overlay: true },
    hardCases: ["keyboard-up", "keyboard-occludes-newest-message"],
    notes:
      "The keyboard is drawn over the thread without a relayout, so the newest incoming message " +
      "and the composer are physically covered. The best a pixel reader can do is the last message " +
      "still visible. This is the case that defines the ceiling of the feature: text under the " +
      "keyboard is not recoverable and must not be guessed.",
    header: { title: "# design-review", subtitle: "63 members" },
    composer: "Message #design-review",
    messages: [
      { kind: "date", text: "Today" },
      {
        from: "them",
        sender: "Elena Fischer",
        text: "Pulled the key row spacing up by two points across all three keyboard heights.",
        time: "1:52 PM",
      },
      { from: "me", sender: "You", text: "Did that fix the thumb reach complaint?", time: "1:58 PM" },
      {
        from: "them",
        sender: "Elena Fischer",
        text: "On the small phone yes. On the Pro Max it made the bottom row worse.",
        time: "2:04 PM",
      },
      { from: "me", sender: "You", text: "Can we scale it per device class instead of a flat value?", time: "2:08 PM" },
      {
        from: "them",
        sender: "Elena Fischer",
        target: true,
        text:
          "That is what I ended up doing. The new spacing reads much better on the 6.3 inch. Can " +
          "you export the dark variant too so I can drop both into the review deck?",
        time: "2:12 PM",
      },
      {
        from: "them",
        sender: "Elena Fischer",
        text: "Actually never mind, I found them in Figma already.",
        time: "2:13 PM",
      },
      {
        from: "them",
        sender: "Elena Fischer",
        text: "Still need the spacing spec written up though, ideally before Thursday's review.",
        time: "2:15 PM",
      },
      {
        from: "them",
        sender: "Ravi Menon",
        text: "I can take the spec if you two are heads down.",
        time: "2:16 PM",
      },
    ],
    expectedOverride: {
      reason:
        "Everything from 2:13 PM down is underneath the keyboard and is not on screen at all. The " +
        "newest readable incoming message is the 2:12 PM one.",
    },
    traps: [
      { text: "q w e r t y u i o p", why: "keyboard key caps: 26 single Latin letters" },
      { text: "I The Sure", why: "predictive-text suggestions above the keys" },
      {
        text: "I can take the spec if you two are heads down.",
        why: "the actual newest message, covered by the keyboard and not readable",
      },
    ],
  },
  {
    id: "sl-06",
    app: "Slack",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "9:30",
    hardCases: ["unread-divider", "bot-message", "continuation-message"],
    notes:
      "A red 'New' divider cuts across the thread, and a continuation message has no name or " +
      "timestamp of its own, so attribution has to be inherited from the post above it.",
    header: { title: "# releases", subtitle: "204 members" },
    composer: "Message #releases",
    messages: [
      { kind: "date", text: "Today" },
      {
        from: "them",
        sender: "Deploy Bot",
        appTag: true,
        text: "aikeyboard-ios 1.4.0 build started. Triggered by sofia.marchetti.",
        time: "5:41 AM",
      },
      {
        from: "them",
        sender: "Deploy Bot",
        appTag: true,
        cont: true,
        text: "Tests passed: 412 of 412. Archive uploaded.",
      },
      {
        from: "them",
        sender: "Deploy Bot",
        appTag: true,
        text: "aikeyboard-ios 1.4.0 promoted to production. 0 rollbacks, 0 failed health checks.",
        time: "6:00 AM",
      },
      { kind: "unread", text: "New" },
      {
        from: "them",
        sender: "Sofia Marchetti",
        text: "1.4.0 is live in the App Store. The ratings dashboard is already picking up Hebrew reviews.",
        time: "9:12 AM",
      },
      { from: "them", sender: "Sofia Marchetti", cont: true, text: "Two people have asked for a floating keyboard." },
      {
        from: "them",
        sender: "Tom Aldridge",
        text: "Can someone own the 1.4.1 hotfix list? I can start it after lunch if nobody else has it.",
        time: "9:30 AM",
      },
    ],
    traps: [
      { text: "New", why: "unread divider label sitting on its own line mid-thread" },
      { text: "aikeyboard-ios 1.4.0 promoted to production.", why: "bot post" },
    ],
  },

  // -------------------------------------------------------------- Messages
  {
    id: "im-01",
    app: "Messages",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "9:41",
    hardCases: ["receipt-line", "nav-badge"],
    notes:
      "Plain iMessage thread. 'Delivered' sits under the outgoing bubble in the same grey as the " +
      "timestamp divider, and the unread badge next to the back chevron is a bare number.",
    header: { title: "Nadia", badge: "12" },
    messages: [
      { kind: "date", text: "Today 9:41 AM" },
      { from: "them", sender: "Nadia", text: "Made it home fine, thanks for driving", time: "8:44 AM" },
      { from: "me", sender: "Me", text: "Any time. That was a long night", time: "8:52 AM" },
      { from: "them", sender: "Nadia", text: "Worth it though", time: "8:55 AM" },
      { from: "them", sender: "Nadia", text: "Morning! Did you see the photos from Saturday?", time: "9:12 AM" },
      { from: "me", sender: "Me", text: "Just went through them. The one by the harbour is great.", time: "9:20 AM" },
      { from: "them", sender: "Nadia", text: "That's my favourite too. I'll print it.", time: "9:24 AM" },
      { from: "me", sender: "Me", text: "Send me one as well", time: "9:31 AM" },
      { from: "them", sender: "Nadia", text: "Are we still on for Thursday?", time: "9:38 AM" },
      { from: "me", sender: "Me", text: "Yes, 7pm at the usual place", time: "9:39 AM", status: "Delivered" },
      { from: "them", sender: "Nadia", text: "Perfect. Bringing my sister, hope that's ok.", time: "9:41 AM" },
    ],
    traps: [
      { text: "Delivered", why: "delivery receipt under the outgoing bubble" },
      { text: "Today 9:41 AM", why: "timestamp divider" },
      { text: "12", why: "unread count in the nav bar" },
    ],
  },
  {
    id: "im-02",
    app: "Messages",
    appearance: "dark",
    language: "hebrew",
    dir: "rtl",
    statusTime: "21:14",
    hardCases: ["reactions", "emoji-in-message"],
    notes:
      "Tapbacks hang off the top corner of the bubbles and overlap them. The message body itself " +
      "ends in emoji, so the boundary between body and reaction is only spatial.",
    header: { title: "יעל" },
    messages: [
      { kind: "date", text: "היום 21:14" },
      { from: "them", sender: "יעל", text: "היום היה ארוך במיוחד", time: "19:52" },
      { from: "me", sender: "אני", text: "גם אצלי. שלוש ישיבות ברצף", time: "20:10" },
      { from: "them", sender: "יעל", text: "לפחות נגמר", time: "20:14" },
      { from: "me", sender: "אני", text: "בדיוק", time: "20:22" },
      { from: "them", sender: "יעל", text: "אני יוצאת מהמשרד עוד מעט", time: "20:35" },
      { from: "me", sender: "אני", text: "מזמין אוכל, מה בא לך?", time: "20:41" },
      { from: "them", sender: "יעל", text: "מה שאתה מזמין תמיד", time: "20:44" },
      { from: "me", sender: "אני", text: "אז פיצה", time: "20:45", status: "נמסר" },
      { from: "them", sender: "יעל", text: "ראית מה קרה במשחק?? 😱", time: "21:10", reactions: ["‼️"] },
      { from: "me", sender: "אני", text: "לא הספקתי, מה פספסתי", time: "21:12", status: "נמסר" },
      {
        from: "them",
        sender: "יעל",
        text: "שתי דקות לסיום, גול ממחצית המגרש 🤯⚽️ אני עדיין בהלם, אתה חייב לראות את החזרה",
        time: "21:14",
        reactions: ["😂 2"],
      },
    ],
    traps: [
      { text: "😂 2", why: "tapback bubble overlapping the message bubble" },
      { text: "נמסר", why: "Hebrew delivery receipt" },
    ],
  },
  {
    id: "im-03",
    app: "Messages",
    appearance: "light",
    language: "hebrew",
    dir: "rtl",
    statusTime: "8:36",
    hardCases: ["last-message-is-outgoing", "read-receipt-with-time"],
    notes:
      "The bottom bubble is the user's own and carries a read receipt with a time in it. It also " +
      "contains a gate code, which is exactly the kind of string a naive reader treats as content.",
    header: { title: "אורי" },
    messages: [
      { kind: "date", text: "היום 8:30" },
      { from: "them", sender: "אורי", text: "היי, נדבר מחר על ההצעה?", time: "7:41" },
      { from: "me", sender: "אני", text: "כן, אני במשרד מתשע", time: "7:50" },
      { from: "them", sender: "אורי", text: "מושלם, אקפוץ אליך", time: "7:52" },
      { from: "me", sender: "אני", text: "מחכה לך", time: "7:58" },
      { from: "them", sender: "אורי", text: "בוקר טוב, אני יוצא לדרך", time: "8:15" },
      { from: "me", sender: "אני", text: "מעולה, נתראה בעוד חצי שעה", time: "8:18", status: "נקרא 8:19" },
      { from: "them", sender: "אורי", text: "יש פקק בכביש 4, אולי אאחר קצת", time: "8:26" },
      { from: "them", sender: "אורי", text: "שלח לי בבקשה את הכתובת של המשרד החדש", time: "8:31" },
      { from: "me", sender: "אני", text: "רוטשילד 45, קומה 8", time: "8:33", status: "נקרא 8:33" },
      { from: "them", sender: "אורי", text: "תודה, ובאיזו קומה החניה?", time: "8:34" },
      { from: "me", sender: "אני", text: "מינוס 2, יש שער עם קוד 1948#", time: "8:36", status: "נקרא 8:36" },
    ],
    expectedOverride: {
      lastMessageIsOutgoing: true,
      reason: "The bottom bubble is outgoing. The newest incoming message is one bubble up.",
    },
    traps: [
      { text: "מינוס 2, יש שער עם קוד 1948#", why: "bottom-most bubble, but the user wrote it" },
      { text: "נקרא 8:36", why: "read receipt with an embedded time" },
    ],
  },
  {
    id: "im-04",
    app: "Messages",
    appearance: "dark",
    language: "mixed",
    dir: "ltr",
    statusTime: "7:22",
    hardCases: ["group-chat", "two-date-dividers", "hebrew-with-english-words", "sender-name-above-text"],
    notes:
      "Group thread crossing midnight, so there are two date dividers on one screen. Sender names " +
      "are tiny grey labels above the bubbles, easy to swallow into the message. The last message " +
      "is Hebrew containing 'rebase', a branch name and a filename.",
    header: { title: "Team Handi" },
    messages: [
      { kind: "date", text: "Yesterday 9:40 PM" },
      {
        from: "them",
        sender: "Dana",
        senderLabel: "Dana",
        text: "Merged the settings refactor. Nothing user visible.",
        time: "9:40 PM",
      },
      { from: "me", sender: "Me", text: "Nice, that unblocks the theme work", time: "9:58 PM" },
      {
        from: "them",
        sender: "Ilan",
        senderLabel: "Ilan",
        text: "מישהו יודע למה ה-CI נופל על iOS 26?",
        time: "10:10 PM",
      },
      { kind: "date", text: "Today 7:15 AM" },
      {
        from: "them",
        sender: "Dana",
        senderLabel: "Dana",
        text: "It's the new privacy manifest. Xcode 26 rejects the old key.",
        time: "7:15 AM",
      },
      { from: "me", sender: "Me", text: "Adding it now", time: "7:19 AM", status: "Delivered" },
      {
        from: "them",
        sender: "Ilan",
        senderLabel: "Ilan",
        text: "מעולה. אחרי שזה עובר תוכל לעשות rebase ל-feature/keyboard-rtl? יש שם conflict ב-Package.resolved",
        time: "7:22 AM",
      },
    ],
    traps: [
      { text: "Ilan", why: "sender label directly above the message body" },
      { text: "Yesterday 10:10 PM", why: "first date divider" },
      { text: "Today 7:15 AM", why: "second date divider mid-screen" },
    ],
  },
  {
    id: "im-05",
    app: "Messages",
    appearance: "light",
    language: "hebrew",
    dir: "rtl",
    statusTime: "11:07",
    keyboard: { lang: "he" },
    hardCases: ["keyboard-up", "sender-name-is-a-phrase", "time-inside-message"],
    notes:
      "The contact is saved as a clinic name, which is a noun phrase rather than a person. The " +
      "message contains two times ('9:15', '20:00') that look like the receipts and dividers " +
      "around it, and the Hebrew keyboard fills the bottom third.",
    header: { title: "מרפאת שיניים - ד\"ר לוין" },
    messages: [
      { kind: "date", text: "היום 11:02" },
      {
        from: "them",
        sender: "מרפאת שיניים - ד\"ר לוין",
        text: "שלום! תזכורת לתור שלך מחר ב-9:15 אצל ד\"ר לוין. נא להגיע 10 דקות לפני.",
        time: "11:02",
      },
      { from: "me", sender: "אני", text: "מאשר, תודה", time: "11:05", status: "נמסר" },
      {
        from: "them",
        sender: "מרפאת שיניים - ד\"ר לוין",
        text: "מצוין. אם צריך לבטל, אפשר להשיב לכאן עד 20:00 היום.",
        time: "11:07",
      },
    ],
    traps: [
      { text: "20:00", why: "a time inside the message body" },
      { text: "מרפאת שיניים - ד\"ר לוין", why: "contact name that parses as a sentence fragment" },
    ],
  },
  {
    id: "im-06",
    app: "Messages",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "4:24",
    hardCases: ["link-preview"],
    notes:
      "A link preview card sits between two real messages. Its headline is a grammatical English " +
      "sentence in a bubble-shaped container, which is the single most convincing decoy in the corpus.",
    header: { title: "Greg" },
    messages: [
      { kind: "date", text: "Today 4:20 PM" },
      { from: "them", sender: "Greg", text: "Did you ever get that OCR thing working?", time: "3:55 PM" },
      { from: "me", sender: "Me", text: "Sort of. Accuracy is fine, picking the right line is the hard part", time: "4:08 PM" },
      { from: "them", sender: "Greg", text: "That's exactly what the article said", time: "4:12 PM" },
      { from: "them", sender: "Greg", text: "This is the piece I was talking about", time: "4:20 PM" },
      {
        from: "them",
        sender: "Greg",
        kind: "card",
        text: "",
        card: { title: "Why on-device OCR still beats the cloud for keyboards", host: "arstechnica.com" },
        time: "4:20 PM",
      },
      { from: "me", sender: "Me", text: "Saved it, will read tonight.", time: "4:22 PM", status: "Delivered" },
      {
        from: "them",
        sender: "Greg",
        text: "The section on Hebrew line detection is the part you'll care about. Worth five minutes.",
        time: "4:24 PM",
      },
    ],
    traps: [
      {
        text: "Why on-device OCR still beats the cloud for keyboards",
        why: "link preview headline rendered in a bubble; reads exactly like a message",
      },
      { text: "arstechnica.com", why: "link preview host" },
    ],
  },
  {
    id: "im-07",
    app: "Messages",
    appearance: "light",
    language: "mixed",
    dir: "rtl",
    statusTime: "13:12",
    hardCases: ["image-attachment", "hebrew-with-english-words"],
    notes:
      "An image bubble with no text at all sits above the caption that belongs to it. A reader that " +
      "walks bubbles bottom-up has to skip a bubble that contains zero characters.",
    header: { title: "מיכל" },
    messages: [
      { kind: "date", text: "היום 13:05" },
      { from: "them", sender: "מיכל", text: "היי! סוף סוף הגיעה המדפסת החדשה", time: "12:31" },
      { from: "me", sender: "אני", text: "איזה יופי, איך היא?", time: "12:44" },
      { from: "them", sender: "מיכל", text: "לוקח זמן להתרגל אבל התוצאות שוות את זה", time: "12:51" },
      { from: "them", sender: "מיכל", kind: "image", text: "", imageLabel: "", time: "13:05" },
      {
        from: "them",
        sender: "מיכל",
        text: "זה מה שהדפסתי אתמול, ה-print quality יצא ממש טוב",
        time: "13:05",
      },
      { from: "me", sender: "אני", text: "וואו, זה מדהים", time: "13:09", status: "נמסר" },
      {
        from: "them",
        sender: "מיכל",
        text: "רוצה שאדפיס לך אחד? תגיד לי איזה size ואני מזמינה מחר",
        time: "13:12",
      },
    ],
    traps: [{ text: "", why: "the image bubble contributes no text and must not shift attribution" }],
  },

  // -------------------------------------------------------------- Telegram
  {
    id: "tg-01",
    app: "Telegram",
    appearance: "dark",
    language: "hebrew",
    dir: "rtl",
    statusTime: "14:21",
    hardCases: ["reply-quote"],
    notes:
      "Telegram stacks the quoted message inside the reply bubble with only a 2px accent bar to " +
      "separate them. The quoted line is a question, so it is more repliable-looking than the answer.",
    header: { title: "אלכס", subtitle: "היה לאחרונה היום ב-14:20", backLabel: "צ'אטים" },
    messages: [
      { kind: "date", text: "היום" },
      { from: "them", sender: "אלכס", text: "בוקר טוב, אני מגיע בסביבות עשר", time: "8:50" },
      { from: "me", sender: "אני", text: "מעולה, אני משאיר את השער פתוח", time: "9:02", status: "read" },
      { from: "them", sender: "אלכס", text: "תודה. להביא משהו?", time: "9:10" },
      { from: "me", sender: "אני", text: "רק שקיות אשפה גדולות אם יש לך", time: "9:15", status: "read" },
      { from: "them", sender: "אלכס", text: "היי, סיימתי לסדר את החצר", time: "13:20" },
      { from: "me", sender: "אני", text: "אלוף. נשאר משהו לזרוק?", time: "13:31", status: "read" },
      { from: "them", sender: "אלכס", text: "רק הקרשים הישנים, שמתי אותם ליד המחסן", time: "13:35" },
      { from: "me", sender: "אני", text: "אני אקח אותם מחר בבוקר", time: "13:52", status: "read" },
      {
        from: "me",
        sender: "אני",
        text: "אתה זוכר איפה שמנו את המפתחות של המחסן?",
        time: "14:02",
        status: "read",
      },
      {
        from: "them",
        sender: "אלכס",
        quoted: { name: "אתה", text: "אתה זוכר איפה שמנו את המפתחות של המחסן?" },
        text: "במגירה השנייה במטבח, מתחת לספר הטלפונים. אם הם לא שם תשאל את יוסי, הוא לקח אותם בשבת",
        time: "14:21",
      },
    ],
    traps: [
      {
        text: "אתה זוכר איפה שמנו את המפתחות של המחסן?",
        why: "quoted line inside the newest bubble; a question, and the user's own words",
      },
      { text: "היה לאחרונה היום ב-14:20", why: "presence line containing a time" },
    ],
  },
  {
    id: "tg-02",
    app: "Telegram",
    appearance: "light",
    language: "mixed",
    dir: "ltr",
    statusTime: "9:26",
    hardCases: ["forwarded-message", "reactions", "hebrew-in-ltr-layout"],
    notes:
      "A forwarded news blurb with an attribution label, then a Hebrew reply in an LTR thread. The " +
      "forwarded text is long, confident English and outranks the actual last message on every " +
      "naive heuristic (length, position near the top, no chrome nearby).",
    header: { title: "Dana Kessler", subtitle: "online", backLabel: "Chats" },
    messages: [
      { kind: "date", text: "Today" },
      { from: "them", sender: "Dana Kessler", text: "Are you at the office today or working from home?", time: "8:32" },
      { from: "me", sender: "Me", text: "Home until lunch, then in.", time: "8:40", status: "read" },
      { from: "them", sender: "Dana Kessler", text: "Good, I'll grab you after. Something came out this morning.", time: "8:44" },
      { from: "me", sender: "Me", text: "Now I'm curious.", time: "9:01", status: "read" },
      {
        from: "them",
        sender: "Dana Kessler",
        forwarded: "Forwarded from TechCrunch",
        text:
          "Apple is opening the keyboard extension sandbox in iOS 27, allowing full network access " +
          "without a container app.",
        time: "9:14",
        reactions: ["🔥 4"],
      },
      { from: "me", sender: "Me", text: "That changes our whole architecture.", time: "9:20", status: "read" },
      {
        from: "them",
        sender: "Dana Kessler",
        text: "נכון, אבל רק ב-iOS 27. אנחנו עדיין צריכים את ה-App Group fallback לשנתיים הקרובות, לא?",
        time: "9:26",
        reactions: ["👍 1"],
      },
    ],
    traps: [
      { text: "Forwarded from TechCrunch", why: "forward attribution label" },
      {
        text: "Apple is opening the keyboard extension sandbox in iOS 27",
        why: "forwarded content, not something Dana wrote",
      },
      { text: "🔥 4", why: "reaction pill with a count" },
    ],
  },
  {
    id: "tg-03",
    app: "Telegram",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "5:46",
    hardCases: ["last-message-is-outgoing"],
    notes:
      "Two outgoing bubbles close the thread, the last one with a single check mark rather than " +
      "two. The incoming question above them is the thing that still wants an answer.",
    header: { title: "Yusuf", subtitle: "last seen recently", backLabel: "Chats" },
    messages: [
      { kind: "date", text: "Today" },
      { from: "them", sender: "Yusuf", text: "Shipment left the port this morning.", time: "16:14" },
      { from: "me", sender: "Me", text: "Good. ETA still Friday?", time: "16:31", status: "read" },
      { from: "them", sender: "Yusuf", text: "Thursday evening if customs is quick.", time: "16:35" },
      { from: "me", sender: "Me", text: "I'll let the warehouse know.", time: "16:50", status: "read" },
      { from: "them", sender: "Yusuf", text: "The warehouse confirmed the pallet count.", time: "17:02" },
      { from: "me", sender: "Me", text: "All forty?", time: "17:11", status: "read" },
      { from: "them", sender: "Yusuf", text: "Thirty eight. Two were damaged in transit.", time: "17:14" },
      { from: "me", sender: "Me", text: "File a claim, we can't absorb that.", time: "17:26", status: "read" },
      { from: "them", sender: "Yusuf", text: "Already did, this morning.", time: "17:28" },
      {
        from: "them",
        sender: "Yusuf",
        text: "Did the invoice for June ever get paid? Accounting is asking.",
        time: "17:40",
      },
      { from: "me", sender: "Me", text: "Checking now.", time: "17:44", status: "read" },
      {
        from: "me",
        sender: "Me",
        text: "Paid on the 3rd, reference 88412. I'll forward the confirmation.",
        time: "17:46",
        status: "sent",
      },
    ],
    expectedOverride: {
      lastMessageIsOutgoing: true,
      reason: "The last two bubbles are outgoing. The newest incoming message is above them.",
    },
    traps: [
      { text: "Paid on the 3rd, reference 88412.", why: "bottom-most bubble, written by the user" },
      { text: "last seen recently", why: "presence line" },
    ],
  },
  {
    id: "tg-04",
    app: "Telegram",
    appearance: "light",
    language: "hebrew",
    dir: "rtl",
    statusTime: "7:48",
    keyboard: { lang: "he" },
    hardCases: ["keyboard-up", "group-chat", "sender-name-is-a-phrase", "scrolled-off-top"],
    notes:
      "Parents' group with the keyboard up. One sender is saved as 'עדי - אמא של רוני', a full " +
      "noun phrase, and it appears twice in a row above two consecutive bubbles.",
    header: { title: "הורים כיתה ג'2", subtitle: "24 חברים", backLabel: "צ'אטים" },
    messages: [
      { kind: "date", text: "היום" },
      {
        from: "them",
        sender: "שירה כהן",
        senderLabel: "שירה כהן",
        text: "בוקר טוב, מישהו יודע אם צריך להביא אישור הורים חתום?",
        time: "7:12",
      },
      {
        from: "them",
        sender: "עדי - אמא של רוני",
        senderLabel: "עדי - אמא של רוני",
        text: "כן, המחנכת ביקשה להביא מודפס. שלחו את זה בטופס ביום ראשון",
        time: "7:18",
      },
      { from: "me", sender: "אני", text: "תודה, הדפסתי אתמול", time: "7:25", status: "read" },
      {
        from: "them",
        sender: "שירה כהן",
        senderLabel: "שירה כהן",
        text: "מעולה, אני ארוץ להדפיס עכשיו",
        time: "7:29",
      },
      {
        from: "them",
        sender: "עדי - אמא של רוני",
        senderLabel: "עדי - אמא של רוני",
        text: "בוקר טוב לכולם! מזכירה שמחר יש טיול שנתי",
        time: "7:40",
      },
      {
        from: "them",
        sender: "עדי - אמא של רוני",
        senderLabel: "עדי - אמא של רוני",
        text: "צריך להביא כובע, בקבוק מים גדול ואוכל לכל היום",
        time: "7:41",
      },
      {
        from: "them",
        sender: "יוסי מזרחי",
        senderLabel: "יוסי מזרחי",
        text: "מה השעה שחוזרים? צריך לארגן הסעות לילדים שההורים עובדים",
        time: "7:48",
      },
    ],
    traps: [
      { text: "עדי - אמא של רוני", why: "sender label that is a noun phrase, printed twice" },
      { text: "24 חברים", why: "member count in the nav bar" },
    ],
  },
  {
    id: "tg-05",
    app: "Telegram",
    appearance: "dark",
    language: "mixed",
    dir: "ltr",
    statusTime: "12:35",
    hardCases: ["group-chat", "mention", "reactions", "hebrew-with-english-words"],
    notes:
      "Public beta group. The newest message opens with an @mention, so the first token of the " +
      "message body looks like an attribution label.",
    header: { title: "AIKeyboard Beta", subtitle: "1,204 members, 89 online", backLabel: "Chats" },
    messages: [
      { kind: "date", text: "Today" },
      {
        from: "them",
        sender: "Lior S.",
        senderLabel: "Lior S.",
        text: "Build 1.4.2 installed fine here, no crash on launch.",
        time: "12:04",
      },
      {
        from: "them",
        sender: "Ahmad N.",
        senderLabel: "Ahmad N.",
        text: "Same. Arabic layout still missing though, any plans?",
        time: "12:11",
      },
      {
        from: "them",
        sender: "Ravid",
        senderLabel: "Ravid",
        text: "ה-swipe typing בעברית עובד ממש טוב בבטא הזאת 👏",
        time: "12:20",
      },
      {
        from: "them",
        sender: "Marta K.",
        senderLabel: "Marta K.",
        text: "Same here on English. Only issue is the number row disappears in landscape.",
        time: "12:28",
      },
      {
        from: "them",
        sender: "Ravid",
        senderLabel: "Ravid",
        text: "@nitai יש תאריך ל-1.5? אנחנו רוצים לעדכן את הצוות שלנו לפני הרבעון הבא",
        time: "12:35",
        reactions: ["👍 12"],
      },
    ],
    traps: [
      { text: "@nitai", why: "mention at the head of the message body, looks like a sender label" },
      { text: "1,204 members, 89 online", why: "group size line in the nav bar" },
      { text: "Ravid", why: "sender label printed twice on one screen" },
    ],
  },

  // ------------------------------------------------------------------ Mail
  {
    id: "ml-01",
    app: "Mail",
    appearance: "light",
    language: "english",
    dir: "ltr",
    statusTime: "9:41",
    hardCases: ["subject-line", "signature-block", "quoted-history"],
    notes:
      "Mail puts four separate blocks of chrome around one body: a 22pt subject line at the top " +
      "that reads like a headline, a To/Details row, a signature with a phone number, and a quoted " +
      "history block. Only the body between them is the message.",
    header: { title: "Contract renewal, Northwind Logistics", backLabel: "Inbox" },
    messages: [
      {
        from: "them",
        sender: "Karen Boyd",
        to: "To: Nitai Aharoni",
        time: "Today 09:14",
        text:
          "Hi Nitai,\n\nLegal came back on the renewal. They are fine with the two year term but " +
          "want the liability cap raised to match last year's contract. Everything else is agreed.\n\n" +
          "Can you confirm by Friday so we can get signatures out before the quarter closes?",
        signature: "Karen Boyd\nHead of Partnerships, Northwind Logistics\n+44 20 7946 0912",
        history: "On Tue, 5 Aug, Nitai Aharoni wrote:\n> Sending over the redlines this afternoon.",
      },
    ],
    traps: [
      { text: "Contract renewal, Northwind Logistics", why: "subject line, largest text on screen" },
      { text: "Head of Partnerships, Northwind Logistics", why: "signature block" },
      { text: "> Sending over the redlines this afternoon.", why: "quoted history, written by the user" },
      { text: "To: Nitai Aharoni", why: "recipient row" },
    ],
  },
  {
    id: "ml-02",
    app: "Mail",
    appearance: "dark",
    language: "hebrew",
    dir: "rtl",
    statusTime: "10:42",
    hardCases: ["subject-line", "signature-block", "rtl-mail"],
    notes:
      "Right-to-left mail: the quote bar moves to the right edge, the To/Details row flips, and " +
      "the signature carries a phone number that OCR will happily read as message content.",
    header: { title: "בקשה להצעת מחיר - פרויקט מקלדת", backLabel: "דואר נכנס" },
    messages: [
      {
        from: "them",
        sender: "משה אלקיים",
        to: "אל: רונית שגב, ניתאי אהרוני",
        time: "אתמול 17:05",
        text:
          "רונית, מצרף את ניתאי לשרשור. הוא זה שבנה את המקלדת שהזכרתי בישיבה.\n\n" +
          "ניתאי, רונית מובילה אצלנו את הרכש. שווה שתדברו ישירות.",
      },
      {
        from: "them",
        sender: "רונית שגב",
        to: "אל: ניתאי אהרוני",
        time: "היום 10:42",
        text:
          "שלום ניתאי,\n\nקיבלנו את ההמלצה עליך מצוות המוצר. אנחנו מחפשים ספק לפיתוח מקלדת עברית " +
          "מותאמת לארגון, כולל תמיכה בהכתבה ובתרגום פנימי.\n\nאשמח לקבל הצעת מחיר ראשונית עד סוף " +
          "השבוע, ולתאם שיחה קצרה בשבוע הבא. האם יום שני בעשר בבוקר מתאים לך?",
        signature: "רונית שגב\nמנהלת רכש, אלפא טכנולוגיות\n03-6412200",
      },
    ],
    traps: [
      { text: "בקשה להצעת מחיר - פרויקט מקלדת", why: "subject line" },
      { text: "מנהלת רכש, אלפא טכנולוגיות", why: "signature block" },
      { text: "אל: ניתאי אהרוני", why: "recipient row" },
      { text: "פרטים", why: "the Details disclosure control" },
    ],
  },
  {
    id: "ml-03",
    app: "Mail",
    appearance: "light",
    language: "mixed",
    dir: "ltr",
    scrolled: true,
    statusTime: "11:37",
    hardCases: ["scrolled-off-top", "signature-block", "quoted-history", "latin-name-hebrew-body"],
    notes:
      "Two-message thread scrolled to the bottom, so the subject line and the whole first mail are " +
      "off screen. The sender's display name is Latin while the body is Hebrew, which breaks any " +
      "language guess made from the name.",
    header: { title: "Re: RTL rendering in the keyboard extension", backLabel: "Inbox" },
    messages: [
      {
        from: "me",
        sender: "Nitai Aharoni",
        to: "To: Ehud Barzilai",
        time: "Today 08:02",
        text:
          "Hi Ehud,\n\nAttaching the traces from the RTL cursor bug. Short version: when the user " +
          "types a Latin word inside a Hebrew sentence, the caret jumps to the visual end of the run " +
          "instead of the logical one, and the next backspace deletes the wrong character.\n\n" +
          "I tried three fixes. Forcing the base writing direction per paragraph works but breaks " +
          "mixed quotes. Overriding the bidi level on the attributed string fixes the caret and " +
          "breaks selection. Letting the system handle it is correct everywhere except inside our " +
          "own suggestion strip.\n\nWhat would you do here?",
      },
      {
        from: "them",
        sender: "Ehud Barzilai",
        to: "To: Nitai Aharoni",
        time: "Today 11:37",
        text:
          "תודה על הפירוט. שתי הערות: ראשית, ה-bidi algorithm של iOS כבר מטפל ברוב המקרים, אז אני " +
          "לא בטוח שצריך override ידני. שנית, ה-NSAttributedString שאתה בונה מאבד את ה-writing " +
          "direction כשהוא עובר דרך ה-App Group.\n\nאפשר לקבוע פגישה מחר ב-14:00?",
        signature: "אהוד ברזילי | Staff iOS Engineer\nehud@example.co.il",
        history: "On Thu, 7 Aug, Nitai Aharoni wrote:\n> Attaching the traces from the RTL cursor bug.",
      },
    ],
    traps: [
      { text: "אהוד ברזילי | Staff iOS Engineer", why: "signature block, mixed script" },
      { text: "ehud@example.co.il", why: "signature address" },
      { text: "> Attaching the traces from the RTL cursor bug.", why: "quoted history in English under a Hebrew body" },
      { text: "Ehud Barzilai", why: "Latin display name attached to a Hebrew message" },
    ],
  },
  {
    id: "ml-04",
    app: "Mail",
    appearance: "dark",
    language: "english",
    dir: "ltr",
    statusTime: "8:05",
    hardCases: ["last-message-is-outgoing", "subject-line"],
    notes:
      "The newest mail in the thread is the user's own reply, sitting at the bottom of the screen " +
      "where every other scene puts the incoming message.",
    header: { title: "Onboarding copy review", backLabel: "Inbox" },
    messages: [
      {
        from: "them",
        sender: "Marta Kowalski",
        to: "To: Nitai Aharoni",
        time: "Yesterday 16:20",
        text:
          "Hi,\n\nI went through the onboarding screens. Screens one and three are clear. Screen two " +
          "asks for keyboard access before it has explained why, and three testers backed out there.\n\n" +
          "Suggested rewrite is in the shared doc. Can you take a look before Thursday's build?",
      },
      {
        from: "me",
        sender: "Nitai Aharoni",
        to: "To: Marta Kowalski",
        time: "Today 08:05",
        text: "Thanks Marta, edits are in the doc. Take another look when you can and I'll cut the build after.",
      },
    ],
    expectedOverride: {
      lastMessageIsOutgoing: true,
      reason: "The bottom mail in the thread is the user's own reply. The incoming one is above it.",
    },
    traps: [
      {
        text: "Thanks Marta, edits are in the doc.",
        why: "bottom-most body on screen, but the user wrote it",
      },
      { text: "Onboarding copy review", why: "subject line" },
    ],
  },
];

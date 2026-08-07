כן. **המוצר אפשרי ב-iOS**, אבל יש בו מלכודת אחת משמעותית: Dictation. אחרי שעברתי על ה-APIs העדכניים של Apple, על Wispr Flow, KeyboardKit והפתרונות הקיימים, הייתי בונה אותו כ־**Keyboard Extension + אפליקציית companion**, ולא כמקלדת שהיא extension בלבד.

### מה אפשר ומה קשה

| יכולת | אפשרי? | איך |
|---|---|---|
| עברית + אנגלית + שפות נוספות | ✅ | Layouts משלך + זיהוי שפה אוטומטי |
| Emoji | ✅ | Unicode emoji keyboard |
| תיקון שגיאות | ✅ | מנוע מקומי ומהיר |
| השלמת המילה הנוכחית | ✅ | מודל מקומי |
| Prediction למילה הבאה | ✅ | מודל קטן local |
| AI Fix למשפט | ✅ | Apple Foundation Models / API בענן |
| Rewrite / Tone | ✅ | אותו מנגנון AI |
| קריאת הטקסט סביב הסמן | ✅ חלקית | דרך `UITextDocumentProxy` |
| Dictation ישירות מהמקלדת | ⚠️ | הבעיה הגדולה |
| לעבוד בכל אפליקציה | כמעט | לא ב-secure fields ובאפליקציות שחוסמות custom keyboards |

Apple נותנת ל-keyboard extension גישה לטקסט שלפני ואחרי הסמן ול-text שנבחר, ויכולת להכניס ולמחוק טקסט. זה בדיוק מה שצריך בשביל autocorrect, autocomplete ופעולות AI. 

## הארכיטקטורה שאני ממליץ עליה

```text
┌────────────────────────────────────┐
│          Main iOS App              │
│                                    │
│  Onboarding / Account / Settings   │
│  Languages / Personal dictionary   │
│  Microphone permission             │
│  Speech-to-Text engine             │
│  Subscription                      │
│  AI configuration                  │
└─────────────────┬──────────────────┘
                  │
             App Group
                  │
┌─────────────────▼──────────────────┐
│       Keyboard Extension           │
│                                    │
│  Hebrew / English keyboard         │
│  Emoji                             │
│  Local autocorrect                 │
│  Next-word predictions             │
│                                    │
│  [🎤] [Fix ✨] [Rewrite]           │
│                                    │
│         UITextDocumentProxy        │
└─────────────────┬──────────────────┘
                  │
                  │ Full Access,
                  │ only when needed
                  ▼
┌────────────────────────────────────┐
│         Your Backend               │
│                                    │
│  AI gateway                        │
│  optional cloud STT                │
│  account/personalization           │
└────────────────────────────────────┘
```

ה-extension עצמו צריך להיות **מהיר, קטן וכמה שיותר local**. Apple מריצה custom keyboard כתהליך מבודד, ובלי Full Access אין לו בכלל network access. המשתמש צריך להדליק `Allow Full Access` מפורשות כדי שתוכל לשלוח טקסט לשרת. 

### 1. ההקלדה הרגילה — לא AI

זו נקודה קריטית: אל תעשה API call ל-LLM אחרי כל אות.

כשמקלידים:

`I would like to m...`

המקלדת צריכה להראות מיד:

`make | meet | mention`

ואחרי:

`I would like to`

אולי:

`know | see | make`

הפעולות האלה צריכות להיות local וב-latency כמעט בלתי מורגש.

Apple עצמה נותנת `UILexicon`, שכולל מילים נפוצות, shortcuts וחלק מהשמות של המשתמש, אבל Apple במפורש מתייחסת אליו כאל **תוספת למנוע autocomplete שאתה בונה בעצמך**, לא כמנוע prediction מלא. 

הייתי מפריד בין שני מנועים:

**Typing engine:** deterministic ומהיר — spelling, autocorrect, capitalization, current-word completion.

**Prediction engine:** מודל language קטן שמקבל למשל את 20–50 המילים האחרונות ומחזיר 3 next-word candidates.

לא צריך GPT בשביל זה.

---

## 2. AI Fix ו-Rewrite — דווקא החלק הקל

נניח שהמשתמש כתב:

> I dont think we should do it because its not make sense

והוא לוחץ:

**✨ Fix**

אתה לוקח את המשפט הנוכחי דרך `documentContextBeforeInput`, או את `selectedText` אם הוא סימן משהו, ושולח:

```text
Correct grammar and spelling.
Preserve meaning and tone.
Preserve the original language.
Return only the corrected text.
```

ומחליף:

> I don't think we should do it because it doesn't make sense.

אפשר באותה דרך להציע:

**Rewrite**

`Clearer · Shorter · Professional · Casual`

Apple מאפשרת ל-keyboard לקרוא את ה-selected text ואת ההקשר סביב הסמן, ולכן UX כזה מתאים מאוד למגבלות המערכת. 

### ואפילו לא חייבים לשלוח את זה ל-OpenAI

ב-iOS 26 Apple פתחה את **Foundation Models framework**, שמאפשר להשתמש במודל Apple Intelligence המקומי ליצירת ושיפור טקסט. הוא מיועד בין היתר ל-text refinement, והוא רץ על המכשיר. 

לכן הייתי עושה:

```text
AI request
     │
     ├── Apple model available?
     │        └── YES → on-device Foundation Models
     │
     └── NO → your backend → cloud LLM
```

זה נותן לך privacy + latency + כמעט אפס cost בחלק גדול מהמקרים.

אבל אסור להניח שהוא יהיה זמין לכל משתמש ולכל שפה, ולכן cloud fallback עדיין חשוב.

---

# 3. שפות — עברית/אנגלית יכול לעבוד טוב מאוד

אפשר להחזיק כמה layouts ולשנות את ה-`primaryLanguage` של המקלדת. בנוסף, `NLLanguageRecognizer` של Apple יודע לזהות שפה ולתת probabilities. 

אני דווקא **לא** הייתי עושה מעבר אגרסיבי של keyboard layout לפי כל מילה.

אם המשתמש הגדיר:

`Languages: Hebrew + English`

הייתי משאיר layout שהוא בחר, אבל מנוע ה-autocorrect וה-prediction יבין code switching:

> אני אשלח לך את ה-document tomorrow

זה חשוב במיוחד בישראל.

למנוע הייתי מכניס language hints מהשפות שהמשתמש הגדיר, וכך לא מנסה לזהות 70 שפות בכל keystroke.

---

# 4. Emoji — פשוט יחסית

תבנה tab נוסף:

```text
ABC  |  😀  |  GIF? 
```

עם:

Recently used  
Smileys  
People  
Food  
Activities  
Objects  
Symbols

והכנסה של Unicode character רגיל.

לא הייתי שומר images של האימוג'ים של Apple בתוך האפליקציה; מבחינת App Store עדיף לעבוד עם Unicode שהמערכת מרנדרת.

---

# 5. הבעיה האמיתית: Dictation

ופה זה נהיה מעניין.

Apple עדיין מתעדת שבאופן היסטורי custom keyboard extension **לא יכול לגשת ישירות למיקרופון**. 

מצד שני Apple היום כן מאפשרת ל-keyboard להצהיר `hasDictationKey`, כלומר המערכת מכירה במקלדות שמספקות מנגנון dictation משלהן — אבל זה לא נותן ל-extension magic microphone entitlement. 

אז איך Wispr Flow עושה את זה?

## מה Wispr עושה בפועל

ההתנהגות הנוכחית שלהם חושפת את הארכיטקטורה.

המשתמש לוחץ במקלדת:

**Start Flow**

Wispr פותח לרגע את ה-main app, מפעיל שם את מנגנון ההקלטה, ואז המשתמש חוזר לאפליקציה שבה כתב.

ב-iOS 26.4 Apple שינתה משהו ביכולת שלהם לחזור אוטומטית לאפליקציה הקודמת. Wispr עצמם מסבירים שהיום צריך לעיתים לבצע **swipe back ידני**, ואז ממשיכים להכתיב מתוך האפליקציה המקורית. 

כלומר בגדול:

```text
WhatsApp
   │
   │ keyboard mic tapped
   ▼
Your Keyboard
   │
   ▼
Your Main App
   │
   ├── AVAudioSession
   ├── microphone
   └── speech transcription
        │
        ▼
User returns to WhatsApp
        │
        ▼
Keyboard receives transcript
        │
        ▼
insertText(...)
```

זה בדיוק האזור שהייתי עושה עליו **technical prototype לפני שאתה משקיע בשאר המוצר**, כי הוא תלוי בהתנהגות מאוד ספציפית של iOS, ו-Wispr עצמם כבר נשברו חלקית בגלל שינוי ב-iOS 26.4. 

Apple גם מחמירה ב-App Review: keyboard צריך להמשיך להיות שימושי בלי Full Access, ואסור שהוא יהיה פשוט conduit לאיסוף פעילות משתמש. 

---

# 6. במה לעשות Speech-to-Text

בתוך **האפליקציה הראשית**, יש לך שלוש אופציות טובות.

Apple Speech נהיה מעניין מאוד: `SpeechAnalyzer` + `SpeechTranscriber` מאפשרים live transcription, כולל מודל on-device, ו-Apple מציינת שהמודל החדש רץ כולו על המכשיר. 

לחלופין, לענן הייתי בודק במיוחד **Deepgram Nova-3**. בפברואר 2026 הם הוסיפו מודל Hebrew production עם streaming ו-Keyterm Prompting — האחרון חשוב מאוד לשמות ישראליים, חברות ומונחים מקצועיים. 

אני הייתי עושה benchmark אמיתי:

```text
                 Hebrew   English   He/En mix   Latency
Apple Speech       ?         ?          ?          ?
Deepgram Nova-3    ?         ?          ?          ?
another STT        ?         ?          ?          ?
```

עם 100–500 הקלטות ישראליות אמיתיות.

אל תבחר ספק לפי benchmark שיווקי באנגלית.

---

# 7. אפשר לחסוך המון עבודה עם KeyboardKit

מצאתי framework די רלוונטי: **KeyboardKit**.

הוא כבר נותן framework ל-custom keyboards, עם autocomplete/autocorrect, predictions, emoji, AI support, dictation ותמיכה בעשרות locales. 

נכון לעכשיו התמחור שלהם הוא בערך:

| Tier | מחיר | רלוונטי לך |
|---|---:|---|
| Basic | $50/mo | autocomplete, שפה אחת |
| Silver | $150/mo | עד 5 שפות + AI |
| Gold | $500/mo | 75+ languages וכל ה-Pro features | 


**אני הייתי מתחיל איתם.**

לא כי הייתי רוצה להיות תלוי בהם לנצח, אלא כי אחרת אתה הולך לבזבז המון זמן על דברים מעצבנים כמו touch areas, shift states, delete-repeat, cursor movement, keyboard sizing, landscape, RTL, accents ו-long press.

Wispr עצמם מפרסמים release notes על דברים כמו taps בין המקשים, dragging בין keys, spacebar cursor ו-keyboard crashes — כלומר אפילו חברה שהמקלדת היא core product שלה עדיין משקיעה בזה הרבה. 

## המוצר שאני הייתי בונה כ-V1

ה-UI של המקלדת:

```text
┌──────────────────────────────────────┐
│  know        think        mean       │
├──────────────────────────────────────┤
│       Q W E R T Y U I O P            │
│        A S D F G H J K L             │
│         Z X C V B N M                │
│                                      │
│ 🌐   😀     space        ✨     🎤   │
└──────────────────────────────────────┘
```

לחיצה על ✨:

```text
┌──────────────────────────────────────┐
│ ✓ Fix   ↻ Rewrite   Shorter   Tone   │
├──────────────────────────────────────┤
│             keyboard                 │
└──────────────────────────────────────┘
```

לחיצה על Rewrite:

```text
Original:
"hey i need this by tomorrow please"

────────────────────────────────────────
Clearer
"Hey, could you please have this ready
by tomorrow?"

Professional
"Could you please have this completed
by tomorrow?"

Shorter
"Can you have this ready by tomorrow?"
```

זה בעיניי הרבה יותר חזק מלעשות "ChatGPT בתוך המקלדת". ה-AI צריך להיות **פעולות קטנות עם zero friction**, לא chatbot.

## סדר הבנייה שאני ממליץ עליו

1. **English + Hebrew keyboard אמיתי**, בעזרת KeyboardKit, כולל emoji, autocorrect ו-next-word.
2. להוסיף **Fix + Rewrite** באמצעות cloud LLM, ובהמשך Foundation Models on-device.
3. לבנות בנפרד prototype ל-**Wispr-style dictation handoff** ולבדוק אותו על iOS 26.4/26.x וב-TestFlight לפני שהוא נהיה תלות קריטית.
4. רק אחרי שזה יציב, להוסיף personalization: שמות, vocabulary, preferred tone ו-learning מהתיקונים שהמשתמש מאשר.

הדבר הכי חשוב מבחינתי: **ה-moat לא יהיה "יש לנו AI".** Grammarly, Wispr ואחרים כבר יודעים לתקן ולנסח. ההזדמנות היא ליצור מקלדת שבה **typing + voice + multilingual + AI editing הם חוויה אחת**, ובמיוחד לעשות Hebrew/English code-switching ברמה שהמקלדות הקיימות לא עושות טוב.

אם הייתי בונה את זה עכשיו, הייתי בוחר **Swift/SwiftUI + KeyboardKit בתחילת הדרך + Apple Foundation Models/cloud LLM + Apple Speech/Deepgram**, כשה-dictation מבודד ארכיטקטונית מה-keyboard כדי ששינוי נוסף של Apple לא ישבור את כל המוצר. 
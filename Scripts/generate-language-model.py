#!/usr/bin/env python3
"""Builds Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/LanguageModel.json.

    python3 Scripts/generate-language-model.py

**What this data is, stated plainly, because the repo's rule is that an invented
reference is worse than a missing one.**

The word orders below are *hand-authored*, ordered by the author's judgement of
how often each word appears in the kind of text this keyboard is typed into:
messages between people in Israel, in English and in Hebrew. They are NOT
measured against a corpus. There is no Zipf count behind them and no frequency
number is claimed anywhere — the only thing asserted is *order*, and only within
a language.

That is enough for the job it does. The engine never needs to know that "the" is
7% of English; it needs to know that "hello" beats "helot", that "מאוד" beats
"מאות", and that "address" beats "a-dress". Rank alone settles all three. Where
rank is not enough — "the approval" against "the approve", which needs to know
that a verb cannot follow a determiner — the local tier deliberately does not
guess and the async tier is asked instead.

**The lists are seeds, not a model.** They cold-start a new install. What makes
the keyboard actually fit its user is `PersonalLanguageModel`, which learns from
what that person types and outranks everything here. These lists are what the
keyboard knows on day zero.

Hebrew words are stored **bare**, without the clitic prefixes ‎ה ב ל מ ו ש כ‎.
`HebrewMorphology` strips a prefix before looking a word up and puts it back
afterwards, so storing "עבודה" makes "לעבודה", "מהעבודה" and "בעבודה" all
reachable from one entry. Storing the inflected forms instead would need dozens
of rows per word and would still miss the combination nobody thought of.
"""

import json
import pathlib

OUT = (
    pathlib.Path(__file__).resolve().parent.parent
    / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/LanguageModel.json"
)


def words(blob):
    """Whitespace-separated words in rank order, de-duplicated, order preserved."""
    seen, out = set(), []
    for word in blob.split():
        key = word.lower()
        if key not in seen:
            seen.add(key)
            out.append(word)
    return out


# ---------------------------------------------------------------------------
# English
# ---------------------------------------------------------------------------
# The closed-class core first (these genuinely are the most common words in any
# English text), then the open-class words a messaging keyboard actually sees:
# times, places, arrangements, apologies, confirmations.

ENGLISH = words(
    """
the be to of and a in that have I it for not on with he as you do at this but his
by from they we say her she or an will my one all would there their what so up out
if about who get which go me when make can like time no just him know take people
into year your good some could them see other than then now look only come over
think also back after use two how our work first well way even new want because any
these give day most us is are was were been has had did does said am being should
must may might shall very much many more less least too again once here where why
while before during until between among through against under above down off own
same such both each few own too very

hi hello hey thanks thank please sorry yes yeah yep no nope ok okay sure fine great
cool perfect awesome nice lovely amazing wonderful excellent

today tomorrow tonight yesterday morning afternoon evening night noon midnight
week weekend month year hour hours minute minutes second seconds moment soon later
early late now already still yet always never sometimes usually often

monday tuesday wednesday thursday friday saturday sunday
january february march april may june july august september october november december

meeting call zoom email message text address phone number name home house office
work job team project deadline schedule calendar appointment reservation booking
ticket order delivery payment invoice receipt price cost budget money bank card
account transfer refund discount

car train bus taxi flight airport station traffic parking road street way route
walk drive ride arrive arriving leave leaving coming going back here there

food lunch dinner breakfast coffee tea water restaurant table kitchen shopping
grocery market store shop mall pharmacy doctor dentist clinic hospital

family kids children baby school kindergarten teacher class homework holiday
vacation birthday anniversary wedding party dinner gift present

send sent sending receive received get got give gave take took bring brought
tell told ask asked answer answered call called text texted write wrote read
check checked confirm confirmed cancel cancelled change changed move moved
finish finished start started stop stopped wait waiting need needed want wanted
help helped meet met see saw know knew think thought remember forgot forget
understand sorry apologize

address approval approve approved approvals available appointment application
arrangement attachment because before believe business calendar certainly
challenge colleague comfortable committee completely condition confirmation
congratulations connection consider continue conversation decision definitely
department describe difference different difficult discussion document
documents education electricity emergency employee equipment especially everyone
everything example excellent exercise experience explain familiar favourite
favorite february finally following friendly furniture generally government
grateful guarantee happening hopefully hospital immediately important impossible
information insurance interested interesting introduce invitation
knowledge language learning listening literally location maintenance management
maybe measure medicine meeting mention message middle midnight moment morning
necessary negotiate neighbour neighbor nervous newsletter normally nothing
notice number occasion offer official opinion opportunity ordinary organise
organize original otherwise package particular password patient payment perfect
performance perhaps permission personal photograph physical picture platform
pleasure position positive possible practice prefer prepare presentation
pressure pretty prevent previous price primary printer priority private
probably problem process produce product professional program progress project
promise property propose protect provide public purchase purpose quality
question quickly quiet quite rather reading really reason receipt receive
recently recommend record reduce reference regarding register regular
relationship remember remind remote repair repeat replace reply report request
require research reservation resource respond response responsible restaurant
result return review right roughly satisfied schedule scheduled search season
second secret section security selection sensitive separate serious service
several shopping should shoulder signature significant similar simple simply
situation slightly slowly software solution somebody someone something sometimes
somewhere special specific standard station statement straight strange strategy
strength stressful structure student subject success suddenly suggest suitable
summary support suppose surprise surprised system technical technology telephone
temperature temporary terrible thanks therefore thinking though thousand through
throughout thursday together tomorrow tonight totally towards traffic training
transfer transport travel treatment trouble tuesday typical understand
understood unfortunately university unless unusual update upgrade urgent useful
usually vacation vehicle version village visit voice volume waiting warning
watching weather wedding weekend welcome whatever whenever whether which
whichever whole window without wonderful working workshop worried writing
written yesterday yourself

hello help held hell helps helped helping
"""
)

# Israeli places, apps and names an English dictionary has never heard of, and
# that this keyboard's users type constantly. Not corpus-derived: this is the
# same class of list as `codeSwitchVocabulary` in SuggestionEngine+Completions,
# and it exists because `UITextChecker` completes "Dizeng" to "Dizziness".
#
# **Nothing from `SharedStore.shippedPersonalDictionary` belongs here.** "Nitai"
# was, and it made `PersonalDictionaryTests` unable to prove anything: those
# tests work by emptying the personal dictionary and checking the same words are
# then destroyed, and a word protected by *this* list survives either way. Two
# lists defending one word means neither can be shown to work.
ENGLISH_LOCAL = words(
    """
Tel Aviv Jerusalem Haifa Herzliya Netanya Ashdod Ashkelon Beersheba Eilat Rishon
Petah Tikva Ramat Gan Givatayim Bnei Brak Holon Bat Yam Raanana Kfar Saba Hod
Hasharon Modiin Rehovot Nesher Tiberias Nazareth Acre Safed Ariel Yavne Lod Ramla
Dizengoff Rothschild Allenby Ibn Gvirol Ben Yehuda Hayarkon Shenkin Florentin
Neve Tzedek Sarona Azrieli Dizengoff Center Carmel Machane Yehuda Levinsky
Wolt Bit Gett Moovit Yango Cibus Tenbis Rappaport Shufersal Rami Levy Victory
Isracard Cal Max Leumi Hapoalim Discount Mizrahi Tefahot Bituach Meuhedet Clalit
Maccabi Leumit Cellcom Partner Pelephone Yes Hot Bezeq
Shekel shekels agorot
Tzachi Yossi Moshe Avi Amit Noa Yael Tamar Shira Maya Roni Omer Ido Guy Dana
Sivan Adi Or Lior Bar Gal Tal Ronen Eyal Oren Gilad Nadav Itai Yonatan Ariel Hadar
shalom toda beseder yalla sababa balagan chutzpah tachles davka stam achla
"""
)

ENGLISH_BIGRAMS = {
    "thank": "you",
    "thanks": "for so a",
    "you": "so are can for know have want tomorrow",
    "so": "much far many good sorry",
    "my": "way phone address name car house office friend",
    "on": "my the way it time",
    "i'm": "on at in going still not sorry here running",
    "in": "the a an about ten five twenty",
    "a": "good great little few lot bit new second minute",
    "the": "same best way first next other last new address meeting office door "
    "weekend end second whole approval invoice receipt",
    "let": "me us you",
    "give": "me you it him her us",
    "talk": "to you later soon",
    "call": "you me back later",
    "good": "morning luck idea night point question",
    "happy": "birthday anniversary holidays new",
    "have": "a to been the",
    "at": "the a home work night my",
    "for": "the a you me it your",
    "of": "course the a it my",
    "how": "are is much many about long",
    "what": "is are do time about",
    "can": "you we be do",
    "could": "you we be",
    "would": "you be like it",
    "should": "be we you",
    "will": "be you it",
    "going": "to be back home",
    "want": "to a it you",
    "need": "to a it your",
    "try": "to it again",
    "sorry": "for about the",
    "no": "problem worries idea",
    "be": "there here a in able back",
    "there": "is are in a",
    "it": "is was will would might",
    "this": "is was week weekend morning",
    "next": "week month year time monday",
    "last": "week month year time night",
    "see": "you it the",
    "waiting": "for on",
    "looking": "for forward at",
    "based": "on in",
    "depends": "on",
    "according": "to",
    "instead": "of",
    "regarding": "the your",
    "attached": "is the",
    "please": "let send call confirm find check",
    "best": "regards way time",
    "take": "care a your it",
    "make": "sure it a",
    "get": "back to it a",
    "pick": "up it me",
    "drop": "off it me",
    "running": "late a",
    "ten": "minutes",
    "five": "minutes",
    "twenty": "minutes",
    "great": "thanks day weekend",
    "very": "much good soon",
    # Two-word keys. The lookup tries the longest suffix first, so these only ever
    # override the one-word row when both words match — `you` is followed by half
    # the language, and `see you` by four things.
    "see you": "tomorrow soon later there",
    "thank you": "so for very",
    "you so": "much",
    "on my": "way",
    "sorry for": "the that",
    "for the": "delay confusion trouble invite",
    "in a": "bit minute second while",
    "let me": "know check see",
    "get back": "to",
    "back to": "you me it",
    "is the": "same best address",
    "attached is": "the",
    "signed the": "contract agreement document",
    "have a": "great good nice",
    "a great": "day weekend week",
    "talk to": "you her him",
    "to you": "later soon tomorrow",
    "running a": "bit little",
    "a bit": "late early more",
}

# ---------------------------------------------------------------------------
# Hebrew
# ---------------------------------------------------------------------------
# Bare stems. The clitics ‎ה ב ל מ ו ש כ‎ are `HebrewMorphology`'s job.

HEBREW = words(
    """
של את לא זה על אני עם מה כל יש הוא היא הם אנחנו אתה אני אם גם או כי אבל רק אז מי איך
למה כמה מתי איפה אין עוד כבר עכשיו היום מחר אתמול הערב הבוקר בבקשה תודה שלום כן בסדר
סליחה רגע נכון בטוח בטוחה אולי כמובן ממש מאוד קצת הרבה יותר פחות הכי טוב טובה נחמד
מצוין מעולה יופי אחלה סבבה יאללה

צריך צריכה רוצה רוצים יכול יכולה יכולים אפשר שולח שולחת שלחתי אשלח מגיע מגיעה מגיעים
אגיע הגעתי אחזור חוזר חוזרת יוצא יוצאת נפגש נדבר מדבר מדברת אמרתי אומר אומרת שואל
שואלת עונה חושב חושבת יודע יודעת מבין מבינה זוכר זוכרת שוכח בודק בודקת אבדוק תבדוק
מחכה מחכים חיכיתי מוכן מוכנה עושה עושים לעשות לשלוח לבדוק לדבר לקבוע לשאול להגיע
לחזור לצאת להיפגש לסגור לפתוח לקנות לשלם לקחת לתת להביא לראות לשמוע לכתוב לקרוא
להזמין לבטל לשנות לחכות לעזור לזכור

בוקר צהריים ערב לילה יום שבוע שבוע שבועיים חודש שנה שעה שעות דקה דקות שניה רבע חצי
ראשון שני שלישי רביעי חמישי שישי שבת סופש חג מועד חופש

פגישה שיחה טלפון נייד מספר כתובת מייל הודעה תור זימון הזמנה תשלום חשבון חשבונית קבלה
מחיר עלות תקציב כסף אשראי העברה החזר הנחה מבצע חוזה מסמך קובץ תמונה סרטון קישור

בית דירה משרד עבודה חדר מטבח סלון חניה רחוב כתובת קומה כניסה שכונה עיר מרכז קניון
חנות סופר מכולת בית קפה מסעדה בר מלון

אוטו רכב רכבת אוטובוס מונית טיסה שדה תעופה תחנה פקק כביש דרך נסיעה הליכה

אוכל ארוחה בוקר צהריים ערב קפה תה מים לחם חלב גבינה סלט פיצה המבורגר שווארמה חומוס
פלאפל סושי קינוח עוגה

ילדים ילד ילדה תינוק גן גננת בית ספר מורה כיתה שיעורי בית חוג משפחה אמא אבא אח אחות
סבא סבתא חבר חברה בעל אישה

רופא רופאה שיניים קופת חולים מרפאה בית חולים תור בדיקה תרופה מרשם ביטוח

עזרה טובה בקשה שאלה תשובה בעיה פתרון רעיון סיבה תשובה החלטה אפשרות ברירה
דחוף חשוב מהר לאט מסובך פשוט ברור מוזר מצחיק עצוב שמח כועס עייף רעב
מאוחר מוקדם אתמול שלשום מחרתיים בהקדם בקרוב תמיד לפעמים בדרך כלל
מצגת פרויקט משימה דוח סיכום פרוטוקול מצליח מסתדר מסודר מתאים נוח
קשר בקשר מושג זמן מקום מצב עניין נושא דבר משהו כלום אף אחד מישהו

מזל טוב חג שמח בהצלחה רפואה שלמה סליחה בשמחה בכיף אין בעיה על הפנים כיף
"""
)

HEBREW_BIGRAMS = {
    "בוקר": "טוב",
    "ערב": "טוב",
    "לילה": "טוב",
    "שבוע": "טוב הבא שעבר",
    "מזל": "טוב",
    "חג": "שמח",
    "יום": "טוב הולדת ראשון שני שלישי רביעי חמישי שישי",
    "תודה": "רבה לך על",
    "רבה": "לך על",
    "סליחה": "על שאני",
    "בבקשה": "תשלח תבדוק תגיד",
    "אני": "מגיע חושב רוצה צריך אשלח בדרך לא כבר",
    "אנחנו": "צריכים נדבר יכולים מגיעים",
    "אתה": "יכול צריך רוצה יודע",
    "את": "יכולה צריכה רוצה יודעת הכתובת החשבונית",
    "צריך": "לבדוק לשלוח להיות לקבוע לסגור",
    "צריכה": "לבדוק לשלוח להיות",
    "רוצה": "לדבר לשאול לבדוק להזמין",
    "אפשר": "לבדוק לדבר לקבוע להזמין",
    "יש": "לי לנו לך משהו סיכוי",
    "אין": "לי בעיה מצב סיכוי",
    "בעוד": "רבע חצי כמה עשר חמש שעה יום",
    "עוד": "מעט קצת פעם",
    "בדרך": "אליך הביתה לעבודה",
    "מה": "קורה נשמע השעה קרה",
    "כמה": "זה עולה שעות דקות",
    "זה": "עולה בסדר נשמע יהיה",
    "מתי": "אתה את נוח",
    "איפה": "אתה את זה",
    "איך": "אתה הולך היה",
    "למה": "לא זה",
    "על": "העזרה זה הפנים",
    "שלחתי": "לך את",
    "תשלח": "לי בבקשה את",
    "אשלח": "לך את",
    "קבעתי": "תור פגישה",
    "לקבוע": "תור פגישה",
    "להזמין": "מונית שולחן תור",
    "הזמנתי": "אוכל שולחן מונית",
    "חוזר": "אליך הביתה",
    "אחזור": "אליך",
    "נדבר": "מחר אחר בהמשך",
    "מגיע": "בעוד עוד אליך",
    "בסדר": "גמור",
    "הכל": "בסדר טוב",
    "כבר": "בדרך שלחתי",
    "לא": "בטוח נכון יודע צריך",
    "בטוח": "שזה",
    "טוב": "מאוד",
    "שבת": "שלום",
    "שנה": "טובה",
    "בהצלחה": "מחר היום",
    "נהיה": "בקשר",
    "אחזור": "אליך",
    "אליך": "מאוחר בהקדם היום",
    "עשר": "דקות",
    "חמש": "דקות",
    "רבע": "שעה",
    "חצי": "שעה",
    "הילדים": "חוזרים בבית",
    "חוזרים": "מהגן הביתה",
    "חוזר": "אליך הביתה מהעבודה",
    "הכנתי": "מצגת",
    # Two-word keys, same rule as the English ones.
    "תודה רבה": "לך על",
    "אני מגיע": "בעוד עוד",
    "אני אחזור": "אליך",
    "בעוד עשר": "דקות",
    "צריך לקבוע": "תור פגישה",
    "אפשר לקבוע": "תור פגישה",
    "יש לי": "פגישה שאלה בקשה",
    "אין לי": "זמן מושג",
    "מה קורה": "אחי",
}

def block(unigram_lists, bigrams):
    """One language's half of the catalogue, with the ranks made unambiguous.

    The de-duplication is case-insensitive and keeps the earlier entry, so a name
    in the local list that is also an ordinary word ("Or", "Bar") resolves to the
    common word's rank rather than sitting twice in one ordered list with two
    different ranks. `matchCase` puts the capital back at the point of use.
    """
    return {
        "unigrams": words(" ".join(" ".join(part) for part in unigram_lists)),
        "bigrams": {key: words(value) for key, value in sorted(bigrams.items())},
    }


CATALOGUE = {
    "schema": 1,
    "source": (
        "Hand-authored rank order, not a measured corpus. Order is the only claim; "
        "no frequency value is asserted. See Scripts/generate-language-model.py."
    ),
    "languages": {
        "en": block([ENGLISH, ENGLISH_LOCAL], ENGLISH_BIGRAMS),
        "he": block([HEBREW], HEBREW_BIGRAMS),
    },
}


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(CATALOGUE, ensure_ascii=False, indent=1, sort_keys=True))
    for code, block in CATALOGUE["languages"].items():
        print(f"{code}: {len(block['unigrams'])} unigrams, {len(block['bigrams'])} bigram keys")
    print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()

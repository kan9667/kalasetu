/// Spoken "how to use this screen" guidance for every read-aloud button.
///
/// Read-back buttons started out reading only the *content* on screen — the
/// caption, the price, the packing steps. For an artisan who cannot read the
/// screen, content alone is not enough: they can hear what the app decided,
/// but not what they are supposed to do about it, which button moves them
/// forward, or which one is destructive. Each page-level button therefore
/// speaks a short orientation first — where you are, what to check, what to
/// tap next — and then the content.
///
/// Every guide lives here rather than inline in the widgets so the whole
/// spoken script of the app can be read, reviewed and corrected in one file.
///
/// English and Hindi only, matching [AppTtsService]'s supported voices. The
/// guide must be spoken in the same language as the content that follows it —
/// a Hindi sentence followed by English content, read by one voice, comes out
/// as mispronounced gibberish.
library;

class TtsGuide {
  final String en;
  final String hi;

  const TtsGuide({required this.en, required this.hi});

  /// The guide in [languageCode], falling back to English for any language
  /// without its own text.
  String forLanguage(String languageCode) =>
      languageCode == 'hi' && hi.isNotEmpty ? hi : en;
}

class TtsPageGuides {
  const TtsPageGuides._();

  /// Add Product, step 3 — the AI-written title and description.
  static const aiListingReview = TtsGuide(
    en: 'This is the listing review screen. From your photo and your voice '
        'note, the app has written a title and a description for your craft. '
        'Listen carefully and check it says what you meant. Use the English '
        'and Hindi buttons to hear it in either language. If a word is wrong, '
        'tap inside the box and correct it yourself. Below that are the '
        'hashtags buyers use to search — remove any that do not fit, and add '
        'your own. If the whole thing is wrong, Regenerate makes the app write '
        'it again. When it is right, tap Looks Good to set your price. This is '
        'what the app has written. ',
    hi: 'यह आपकी सूची जाँचने वाली स्क्रीन है। आपकी तस्वीर और आपकी आवाज़ से ऐप ने '
        'आपके सामान का नाम और विवरण लिखा है। ध्यान से सुनिए और जाँचिए कि यह वही '
        'है जो आप कहना चाहते थे। ऊपर अंग्रेज़ी और हिन्दी के बटन दबाकर आप इसे किसी '
        'भी भाषा में सुन सकते हैं। अगर कोई शब्द ग़लत है, तो डिब्बे के अंदर दबाकर उसे '
        'खुद ठीक कीजिए। नीचे वे हैशटैग हैं जिनसे ग्राहक खोजते हैं — जो ठीक न लगे उसे '
        'हटाइए और अपने जोड़िए। अगर पूरा विवरण ही ग़लत है तो फिर से बनाएँ दबाकर ऐप से '
        'दोबारा लिखवाइए। सब सही होने पर सब सही है दबाकर मूल्य तय कीजिए। ऐप ने यह '
        'लिखा है। ',
  );

  /// Add Product, step 4 — the suggested price.
  static const pricing = TtsGuide(
    en: 'This is the price screen. The app has suggested a fair price by '
        'looking at what crafts like yours are selling for. You are not forced '
        'to accept it. Drag the round handle on the bar to the right to raise '
        'your price, or to the left to lower it, and the big rupee figure at '
        'the top changes as you drag. Under the left end of the bar is your '
        'hard floor price — the least this craft can sell for and still cover '
        'your materials and your labour. Never settle below it, or you are '
        'paying to work. The two panels underneath, Cost Breakdown and Market '
        'Benchmarks, open when tapped and show how the app worked the price '
        'out. When you are happy with the number, tap Next. ',
    hi: 'यह मूल्य तय करने वाली स्क्रीन है। आपके जैसे सामान किस दाम पर बिक रहे हैं, '
        'यह देखकर ऐप ने एक उचित मूल्य सुझाया है। इसे मानना ज़रूरी नहीं है। पट्टी पर '
        'बने गोल बटन को दाहिनी ओर खींचिए तो दाम बढ़ेगा, बाईं ओर खींचिए तो घटेगा, और '
        'ऊपर लिखी बड़ी रकम साथ-साथ बदलती जाएगी। पट्टी के बाएँ सिरे के नीचे आपका '
        'न्यूनतम मूल्य लिखा है — इतने में ही आपकी सामग्री और मेहनत का ख़र्च निकलता '
        'है। इससे नीचे कभी मत जाइए, वरना आप काम करके भी घाटे में रहेंगे। नीचे दिए दो '
        'हिस्से — लागत का ब्यौरा और बाज़ार के भाव — दबाने पर खुलते हैं और बताते हैं कि '
        'ऐप ने यह दाम कैसे निकाला। दाम ठीक लगे तो आगे दबाइए। ',
  );

  /// Add Product, step 5 — the final confirmation before publishing.
  static const confirmPublish = TtsGuide(
    en: 'This is the last screen before your craft goes online. Nothing has '
        'been published yet. Listen to the whole listing one more time. If '
        'anything is wrong, use the back arrow at the top to go and fix it. '
        'When everything is correct, tap List Product Now, and buyers will be '
        'able to see and order your craft. This is your final listing. ',
    hi: 'आपका सामान ऑनलाइन जाने से पहले यह आख़िरी स्क्रीन है। अभी कुछ भी प्रकाशित '
        'नहीं हुआ है। पूरी सूची एक बार और ध्यान से सुनिए। अगर कुछ भी ग़लत है तो ऊपर '
        'दिए तीर के निशान से पीछे जाकर उसे ठीक कीजिए। सब सही होने पर उत्पाद अभी '
        'लिस्ट करें दबाइए, फिर ग्राहक आपका सामान देख और मँगा सकेंगे। यह आपकी अंतिम '
        'सूची है। ',
  );

  /// Packaging suggestions sheet, opened from an order.
  static const packaging = TtsGuide(
    en: 'This is the packing guide for this order. Follow these steps in the '
        'same order before you hand the parcel to the delivery agent. Packing '
        'it properly is what stops the item breaking on the way — if it '
        'arrives damaged, the buyer gets a refund and you lose both the craft '
        'and the payment. The steps are as follows. ',
    hi: 'यह इस ऑर्डर को पैक करने की जानकारी है। डिलीवरी वाले को पार्सल देने से पहले '
        'इन चरणों का इसी क्रम में पालन कीजिए। सही तरीके से पैक करने पर ही सामान '
        'रास्ते में टूटने से बचता है — अगर वह टूटा हुआ पहुँचा तो ग्राहक को पैसे वापस मिल '
        'जाते हैं और आपका सामान भी जाता है और पैसा भी। चरण इस प्रकार हैं। ',
  );

  /// Social Media Helper — the generated caption and hashtags.
  static const socialMedia = TtsGuide(
    en: 'This is the social media helper. The app has written a post for your '
        'craft that you can share on WhatsApp, Instagram or Facebook. Listen '
        'and check it describes your work correctly. To change any word, tap '
        'inside the caption box and edit it. The hashtags below the caption '
        'help new buyers find you, so keep them. When you are ready, tap Copy '
        'to copy the whole post, then paste it into the app you want to share '
        'it on. This is the caption. ',
    hi: 'यह सोशल मीडिया सहायक है। ऐप ने आपके सामान के लिए एक पोस्ट लिखी है जिसे आप '
        'व्हाट्सएप, इंस्टाग्राम या फ़ेसबुक पर साझा कर सकते हैं। सुनिए और जाँचिए कि यह '
        'आपके काम को सही बताती है या नहीं। कोई शब्द बदलना हो तो लिखे हुए डिब्बे के '
        'अंदर दबाकर उसे ठीक कीजिए। नीचे दिए हैशटैग नए ग्राहकों को आप तक पहुँचाते हैं, '
        'इसलिए उन्हें रहने दीजिए। तैयार होने पर कॉपी दबाकर पूरी पोस्ट कॉपी कीजिए, फिर '
        'जिस ऐप पर साझा करना है उसमें चिपका दीजिए। पोस्ट इस प्रकार है। ',
  );

  /// Registration form — spoken walk-through of the fields.
  static const register = TtsGuide(
    en: 'This is the registration form. Four things are required: your full '
        'name, your ten digit mobile number, the craft you make, and your '
        'village or cluster along with your state. Your years of experience '
        'and your Pehchan artisan card number are optional — you can leave '
        'them empty and add them later. Fill the boxes from top to bottom, '
        'then tap Create Account at the bottom. If you cannot fill this '
        'yourself, ask your cluster coordinator or a local N G O to help you. ',
    hi: 'यह पंजीकरण फ़ॉर्म है। चार बातें ज़रूरी हैं — आपका पूरा नाम, आपका दस अंकों का '
        'मोबाइल नंबर, आप कौन सा काम करते हैं, और आपका गाँव या क्लस्टर तथा राज्य। '
        'आपके काम के कितने साल हुए और आपका पहचान कार्ड नंबर — ये दोनों ज़रूरी नहीं '
        'हैं, इन्हें खाली छोड़कर बाद में भी भर सकते हैं। ऊपर से नीचे तक डिब्बे भरिए, फिर '
        'सबसे नीचे खाता बनाएँ दबाइए। अगर आप खुद नहीं भर पा रहे हैं, तो अपने क्लस्टर '
        'समन्वयक या स्थानीय एनजीओ से मदद लीजिए। ',
  );

  /// My Orders — one short clause before each order card's summary. Kept to a
  /// single sentence on purpose: this button sits on every card in a list and
  /// is tapped repeatedly, so a full page walk-through would be read out again
  /// and again before the artisan reaches the detail they actually wanted.
  static const orderCardLead = TtsGuide(
    en: 'Order details. Tap the card itself to open it and see the buyer '
        'address and the delivery date. ',
    hi: 'ऑर्डर का विवरण। ग्राहक का पता और पहुँचाने की तारीख़ देखने के लिए कार्ड पर '
        'दबाइए। ',
  );
}

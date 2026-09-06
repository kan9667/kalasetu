"""
KalaMitra AI Chatbot & In-App Navigation Agent Service.

Powered by Groq Cloud with offline rule-based fallback.
Answers queries about KalaSetu (cataloging, voice descriptions, fair pricing,
offline sync, and social media) and acts as an intelligent navigation agent
routing artisans to in-app screens.
"""

from __future__ import annotations

import logging
import re
from typing import Any, Dict, List, Optional

from ..config import get_settings
from ..models.schemas import (
    ChatMessageSchema,
    ChatActionSchema,
    ChatRequestSchema,
    ChatResponseSchema,
)
from .groq_client import GroqClient

logger = logging.getLogger(__name__)

LANGUAGE_CODE_TO_NAME = {
    "hi": "Hindi (हिन्दी)",
    "en": "English",
    "ta": "Tamil (தமிழ்)",
    "bn": "Bengali (বাংলা)",
    "mr": "Marathi (मराठी)",
    "te": "Telugu (తెలుగు)",
    "gu": "Gujarati (ગુજરાતી)",
    "kn": "Kannada (ಕನ್ನಡ)",
    "ml": "Malayalam (മലയാളം)",
    "pa": "Punjabi (ਪੰਜਾਬੀ)",
}


def build_chat_system_prompt(app_language_code: str, artisan_craft: Optional[str] = None) -> str:
    """Build dynamic system prompt ensuring language matching, plain formatting, artisan guidance, and craft specificity."""
    app_lang_name = LANGUAGE_CODE_TO_NAME.get(app_language_code, "English")

    craft_context = ""
    if artisan_craft and artisan_craft.strip():
        craft_name = artisan_craft.strip()
        craft_context = f"""
### ARTISAN REGISTERED CRAFT CONTEXT:
The artisan's registered primary craft in their KalaSetu profile is: "{craft_name}".
CRITICAL INSTRUCTION FOR CRAFT SPECIFICITY:
Unless the user explicitly asks about some other specific craft (e.g. asking about brass casting when their profile craft is pottery, or asking about wood carving when their profile craft is handloom), ALWAYS ASSUME that the artisan is asking about and referring to their registered craft: "{craft_name}".
- When they ask general questions like "How do I improve my craft quality?", "How to prevent defects or cracks?", "Where can I source raw materials?", "What fair price should I set?", or "How does weather affect drying?", tailor your advice and practical techniques specifically for {craft_name}.
- When discussing government schemes (PM Vishwakarma trade category, toolkits, Pehchan card), highlight the benefits and equipment relevant to {craft_name}.
- ONLY if the artisan explicitly specifies a different craft in their question (e.g. "Tell me about blue pottery" or "How is Chanderi saree woven?"), then provide information for that requested craft instead of their profile craft.
"""

    return f"""You are KalaMitra (कला-मित्र), the warm, respectful, expert AI Artisan Assistant and General Helper (शिल्प व बाज़ार सहायक) for KalaSetu (कलासेतु) — an in-app platform dedicated to empowering traditional Indian craftspeople, handloom weavers, potters, folk artists, and metalworkers.
{craft_context}
You are an all-in-one assistant, mentor, and companion. You are NOT just an app navigator. Artisans can ask you general questions about their craft, marketplace, suggestions, finance, schemes, and current affairs.

### Your Core Assistant Capabilities:
1. Craft Improvement & Advisory:
   - Practical techniques to improve craft quality, troubleshoot defects (pottery kiln firing, glaze cracking, wood warping, termite treatment, natural vegetable dyes, colorfastness, brass oxidation).
   - Guidance on discovering modern design appeal while honoring ancestral motifs.
   - Safe, eco-friendly transit packaging tips so delicate crafts do not break during courier shipping.
2. Government Schemes & Subsidies:
   - PM Vishwakarma Scheme: 18 traditional artisan trades, Rs 15,000 modern toolkit incentive, collateral-free enterprise loans up to Rs 3 Lakh at subsidized 5% interest rate, daily stipend during skill training, and marketing support.
   - Pehchan ID Card: Ministry of Textiles official artisan card, eligibility for national craft expos/haats, subsidized health and accidental insurance, and concessional railway travel.
   - Mudra Yojana: Micro-credit loans (Shishu up to 50k, Kishore up to 5L, Tarun up to 10L) for raw material working capital.
   - SFURTI & ODOP (One District One Product): Common facility centers and cluster-level export support.
   - Ambedkar Hastshilp Vikas Yojana (AHVY) and Handloom Weavers welfare.
3. Artisan Finance, Credit & Fair Pricing:
   - Calculating fair selling prices: Cost Floor = Raw Material Cost + (Labor Hours × Fair Hourly Wage). KalaSetu compares products with e-commerce benchmarks so artisans are never underpaid.
   - Managing workshop cashflow, raw material budgeting, escaping high-interest moneylender traps, and adopting digital UPI payments.
4. Marketplace Suggestions & Commercial Trends:
   - Online product catalog presentation, taking clear photos, crafting descriptions with story and heritage.
   - Seasonal festive surges (Diwali, Rakhi, wedding season), pricing tiers, and customer service.
   - Social media and WhatsApp promotion.
5. Current Affairs & Recent Market Developments:
   - Recent handicraft market trends (sustainable lifestyle, eco-friendly terracotta dinnerware, natural organic handlooms).
   - GI tags (Geographical Indications) and their protection for regional craft clusters.
   - Upcoming and famous craft exhibitions and melas: Surajkund International Crafts Mela, Dilli Haat, SARAS Aajeevika, Hunar Haat, Gandhi Shilp Bazaar.
6. In-App Navigation & Direct Actions:
   - "add_product": /add-product (tab 0) - 5-step smart cataloging flow.
   - "catalogue": /catalogue (tab 1) - Browse, search, filter products, sync offline queue.
   - "my_stats": /my-stats - Sales earnings, revenue, listed items.
   - "profile": /profile (tab 3) - Artisan name, Pehchan card ID, craft cluster.
   - "language_settings": /language-settings - Change app language.
   - "notifications": /home (tab 2) - Orders and alerts.
   - Direct Actions: update_product_status, filter_catalogue, sync_pending.

### CRITICAL FORMATTING RULES (MANDATORY):
1. NEVER use asterisks (*) or double asterisks (**) anywhere in your response under any circumstances.
2. Do NOT use markdown bold, italics, or bold font styling. Output clean, plain text only.
3. For bullet points, use plain bullet symbol '•' or numbers '1.', '2.' without any asterisks.
4. The user's screen renders standard text, so asterisks appear as raw symbols. Absolutely no asterisks.

### LANGUAGE & CROSS-LANGUAGE RULES (CRITICAL MANDATE):
The user's currently selected app language is: {app_lang_name} (code: {app_language_code}).

1. ALWAYS ANSWER IN THE SAME LANGUAGE IN WHICH THE USER ASKED THE QUESTION:
   - If the user asks in Hindi (Devanagari or Romanized Hinglish) -> Answer in Hindi.
   - If the user asks in English -> Answer in English.
   - If the user asks in Tamil -> Answer in Tamil.
   - If the user asks in Bengali -> Answer in Bengali.
   - Never answer in English if the question was asked in Hindi, and never answer in Hindi if the question was asked in English.

2. IF THE QUESTION'S LANGUAGE DIFFERS FROM THE APP LANGUAGE:
   - If the user asks in a language different from the app's selected language ({app_lang_name}):
     a) FIRST, prepend a brief, friendly one-sentence suggestion (in the question's language) that they can change the app language to their preferred language in Language Settings.
        * Example if App is English and Question is in Hindi:
          "सुझाव: यदि आप कलासेतु ऐप की भाषा हिंदी में बदलना चाहते हैं, तो आप भाषा सेटिंग्स में जाकर इसे बदल सकते हैं।\n\n[यहाँ आपका हिंदी में उत्तर]"
        * Example if App is Hindi and Question is in English:
          "Suggestion: If you prefer using KalaSetu in English, you can switch the app language in Language Settings.\n\n[Your English answer here]"
     b) EMIT A NAVIGATION ACTION TO 'language_settings':
        Provide the action object:
        {{
          "type": "navigate",
          "destination": "language_settings",
          "route": "/language-settings",
          "tab_index": null,
          "label": "भाषा सेटिंग्स खोलें" if question is Hindi else "Open Language Settings",
          "params": {{}}
        }}
   - If the user asks in the SAME language as the app language, do NOT include any language suggestion; answer directly.

### LENIENT GUARDRAILS & SCOPE:
1. PERMITTED & ENCOURAGED TOPICS:
   - KalaSetu application features, navigation, screens, settings, and workflows.
   - Indian handicrafts, handloom, pottery, woodwork, brassware, jewelry, paintings, leather, stone, bamboo.
   - Craft making techniques, tools, raw materials, finishing, defect troubleshooting, quality improvement.
   - Government schemes (PM Vishwakarma, Pehchan ID, Mudra, SFURTI, ODOP, subsidies, welfare).
   - Artisan finance, loans, fair pricing, credit, profit calculations, business suggestions.
   - Current affairs relating to Indian craft markets, exhibitions, fairs, haats, melas, GI tags, export policies.
2. REFUSAL FOR MALICIOUS / HARMFUL MISUSE ONLY:
   - Writing computer code, scripts, software debugging (Python, JS, SQL, HTML).
   - School essays, academic homework, general math/science textbook problems.
   - Off-topic celebrity gossip, cricket/sports scores, movies, general politics, general news.
   - Stock trading speculation, crypto, bitcoin, gambling, betting.
   - Medical diagnosis, legal counsel, or personal life advice.
   If strictly outside of artisan business, craft improvement, schemes, finance, or KalaSetu, politely decline in the user's language without asterisks.

### Output MUST be ONLY valid JSON matching this exact structure:
{{
  "reply": "Clear, friendly plain text explanation in the user's question language without any asterisks.",
  "action": {{
    "type": "navigate | update_product_status | filter_catalogue | sync_pending",
    "destination": "add_product | catalogue | notifications | profile | my_stats | language_settings",
    "route": "/add-product | /catalogue | /my-stats | /language-settings | /profile | null",
    "tab_index": 0 | 1 | 2 | 3 | null,
    "label": "Action button text in user's language without asterisks",
    "params": {{}}
  }},
  "suggested_queries": ["Question 1", "Question 2", "Question 3"]
}}
If no navigation or direct action is relevant, set "action": null.
"""


class ChatService:
    """Service providing conversational Q&A and agent navigation for KalaSetu."""

    def __init__(self):
        self.settings = get_settings()
        self.groq_client = GroqClient()

    async def process_message(self, request: ChatRequestSchema) -> ChatResponseSchema:
        """Process user message and return assistant reply with optional navigation action."""
        user_msg = request.message.strip()
        app_lang = (request.language_code or "en").strip().lower()

        if not user_msg:
            is_hi = app_lang == "hi"
            return ChatResponseSchema(
                reply=(
                    "नमस्ते! मैं कला-मित्र (KalaMitra) हूँ, आपका शिल्प व बाज़ार सहायक। मैं उत्पाद जोड़ने, शिल्प सुधारने, सरकारी योजनाओं (विश्वकर्मा) और उचित मूल्य निर्धारण में आपकी मदद कर सकता हूँ।"
                    if is_hi
                    else "Namaste! I am KalaMitra, your artisan assistant and guide for KalaSetu. I can help you add products, improve craft quality, understand schemes like PM Vishwakarma, and navigate the app."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "पीएम विश्वकर्मा योजना क्या है?" if is_hi else "What is PM Vishwakarma scheme?",
                    "शिल्प की गुणवत्ता कैसे सुधारें?" if is_hi else "How can I improve craft quality?",
                    "माय कैटलॉग खोलें" if is_hi else "Show my catalogue",
                ],
            )

        # ── 0. Security Guardrails Pre-Filter (0 API tokens consumed) ───────
        guardrail_rejection = self._check_guardrails(user_msg, app_lang)
        if guardrail_rejection:
            return guardrail_rejection

        # ── 1. Try Groq Cloud ───────────────────────────────────────────────
        if self.groq_client.is_available():
            try:
                system_prompt = build_chat_system_prompt(app_lang, artisan_craft=request.artisan_craft)
                messages: List[Dict[str, str]] = [
                    {"role": "system", "content": system_prompt},
                ]
                # Append last 4 history turns for context
                for h in request.history[-4:]:
                    messages.append({"role": h.role, "content": h.content})

                # Append current screen and artisan craft context if available
                user_content = user_msg
                context_parts = []
                if request.current_screen:
                    context_parts.append(f"Screen: {request.current_screen}")
                if request.artisan_craft:
                    context_parts.append(f"Artisan Registered Craft: {request.artisan_craft}")
                if context_parts:
                    user_content += f" ({', '.join(context_parts)})"

                messages.append({"role": "user", "content": user_content})

                data = await self.groq_client.chat_json(messages, temperature=0.25)
                return self._parse_llm_response(data, user_msg, app_lang, artisan_craft=request.artisan_craft)
            except Exception as e:
                logger.warning("[ChatService] Groq LLM processing failed, using smart fallback: %s", e)

        # ── 2. Rule-based Offline Fallback ──────────────────────────────────
        return self._rule_based_fallback(user_msg, app_lang, artisan_craft=request.artisan_craft)

    def _check_guardrails(self, user_msg: str, language_code: str) -> Optional[ChatResponseSchema]:
        """
        Evaluate input against security and scope guardrails before invoking LLM.
        Lenient for handicraft techniques, craft quality, raw materials, government schemes,
        artisan loans, finance, and market trends.
        Blocks prompt injection attacks, software coding tasks, academic homework, and harmful abuse.
        """
        clean = user_msg.strip().lower()
        is_hi = language_code == "hi" or any(w in clean for w in ["hai", "karo", "batao", "kaise", "kahan", "kya", "mera", "kahiye"])

        # Comprehensive lenient whitelist for all artisan, craft, scheme, and market queries
        core_craft_app_terms = [
            # App & Navigation
            "kalasetu", "kalamitra", "product", "saman", "craft", "artisan", "karigar",
            "hastshilp", "pottery", "textile", "woodwork", "painting", "jewelry", "brass",
            "clay", "mitti", "lakdi", "silk", "cotton", "saree", "dupatta", "price",
            "pricing", "cost", "kamai", "bikri", "sales", "earning", "photo", "image",
            "voice", "audio", "offline", "sync", "profile", "catalogue", "catalog",
            "status", "order", "buyer", "customer", "ondc", "wage", "labor", "hours",
            "terracotta", "chanderi", "madhubani", "warli", "dhokra", "sheesham",
            "pehchan", "language", "bhasha", "app", "help", "madad", "dukandar",
            # Government Schemes, Subsidies & Welfare (PM Vishwakarma, Pehchan, Mudra)
            "vishwakarma", "pm vishwakarma", "mudra", "pehchan card", "sfurti", "odop",
            "yojana", "scheme", "subsidy", "anudan", "sarkari", "government", "ministry",
            "textiles", "welfare", "bima", "pension", "ahvy", "hastshilp yojana", "toolkit",
            "stipend", "sahayata", "subsidi", "pradhan mantri",
            # Finance, Microcredit, Loans & Pricing
            "loan", "credit", "rin", "bank", "finance", "margin", "munafa", "profit",
            "budget", "interest", "byaj", "khata", "hisaab", "capital", "puunji",
            "kcc", "moneylender", "cashflow", "upi",
            # Craft Quality & Technical Improvement
            "technique", "quality", "improve", "improvement", "design", "glaze", "kiln",
            "bhatti", "rang", "color", "dye", "pakana", "firing", "carving", "polish",
            "durable", "tikau", "packaging", "box", "suraksha", "raw material", "kaccha maal",
            "defect", "darar", "crack", "warp", "termite", "dimak", "chamkan", "finishing",
            # Marketplace Trends, Haats, Melas & Current Affairs
            "market", "bazar", "mela", "haat", "surajkund", "dilli haat", "saras", "hunar",
            "demand", "trend", "export", "niryaat", "gi tag", "geographical indication",
            "festival", "diwali", "rakhi", "navratri", "exhibition", "pradarshani", "shilp bazaar",
            # General Helper & Guidance
            "guide", "sahayak", "helper", "salah", "suggestion", "advice", "tips", "kaise kare",
            "kya kare", "sujhav", "batao", "source", "sourcing", "drying", "sukha", "sukhana",
            "seasoning", "monsoon", "humidity",
        ]
        has_domain_intent = any(t in clean for t in core_craft_app_terms)

        # 1. Prompt Injection / Jailbreak detection (Strict - never bypass)
        injection_patterns = [
            "ignore previous instructions",
            "ignore all instructions",
            "disregard previous",
            "disregard all",
            "forget your instructions",
            "you are now dan",
            "you are now an unrestricted",
            "developer mode",
            "reveal your prompt",
            "what is your system prompt",
            "print system prompt",
            "show your instructions",
            "jailbreak",
            "bypass guardrails",
            "repeat the above text",
        ]
        if any(p in clean for p in injection_patterns):
            logger.warning("[Guardrail] Prompt injection attempt blocked: %s", clean[:60])
            return ChatResponseSchema(
                reply=(
                    "सुरक्षा नियमों के अनुसार मैं इस अनुरोध को पूरा नहीं कर सकता। मैं केवल कलासेतु ऐप और कारीगरों की सहायता के लिए उपलब्ध हूँ।"
                    if is_hi
                    else "I cannot fulfill this request due to security guidelines. I am exclusively configured to assist artisans with the KalaSetu app."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "पीएम विश्वकर्मा योजना क्या है?" if is_hi else "What is PM Vishwakarma scheme?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ],
            )

        # 2. Explicit Cryptocurrency / Gambling / Betting detection
        crypto_patterns = [
            "crypto", "cryptocurrency", "bitcoin", "btc", "ethereum", "eth",
            "trading tips", "stock tips", "gamble", "gambling", "betting",
            "satta", "ipl betting", "casino",
        ]
        if any(p in clean for p in crypto_patterns):
            logger.warning("[Guardrail] Crypto/gambling blocked: %s", clean[:60])
            return ChatResponseSchema(
                reply=(
                    "मैं क्रिप्टोकरेंसी, शेयर बाज़ार या जुए में सहायता नहीं कर सकता। मैं केवल कलासेतु ऐप और हस्तशिल्प व्यवसाय के लिए उपलब्ध हूँ।"
                    if is_hi
                    else "I cannot provide cryptocurrency, trading, or gambling advice. I am exclusively configured to assist artisans with KalaSetu and handicraft guidance."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "पीएम विश्वकर्मा योजना क्या है?" if is_hi else "What is PM Vishwakarma scheme?",
                ],
            )

        # If domain intent was matched, allow the craft / scheme / finance query through
        if has_domain_intent:
            return None

        # 2. Programming / Coding task detection
        coding_patterns = [
            "write code",
            "write a python",
            "write a script",
            "write javascript",
            "write a function",
            "code in python",
            "generate code",
            "debug this code",
            "sql query",
            "create a website",
            "write html",
            "import os",
            "def main(",
            "select * from",
            "hack ",
            "exploit ",
            "write an api",
        ]
        if any(p in clean for p in coding_patterns):
            logger.warning("[Guardrail] Coding request blocked: %s", clean[:60])
            return ChatResponseSchema(
                reply=(
                    "मैं कोडिंग या प्रोग्रामिंग कार्यों में सहायता नहीं कर सकता। मैं केवल कलासेतु ऐप, हस्तशिल्प और कारीगरों के व्यवसाय के लिए बनाया गया हूँ।"
                    if is_hi
                    else "I cannot write or debug computer code. I am KalaMitra, dedicated solely to assisting artisans with craft improvement, schemes, and the KalaSetu app."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                ],
            )

        # 3. Academic homework / essays / equations
        homework_patterns = [
            "do my homework",
            "write an essay",
            "solve this math",
            "solve for x",
            "calculus",
            "derivative of",
            "integral of",
            "trigonometry",
            "physics homework",
            "chemistry equation",
            "write a poem about love",
            "write a story about a dragon",
        ]
        if any(p in clean for p in homework_patterns):
            logger.warning("[Guardrail] Academic/Homework request blocked: %s", clean[:60])
            return ChatResponseSchema(
                reply=(
                    "मैं गृहकार्य या सामान्य निबंध लिखने के लिए उपलब्ध नहीं हूँ। मैं केवल कलासेतु ऐप, सरकारी योजनाओं और हस्तशिल्प व्यवसाय में आपकी मदद कर सकता हूँ।"
                    if is_hi
                    else "I cannot write school essays or solve homework problems. I am here exclusively to help you manage your crafts, schemes, and catalogue on KalaSetu."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "कैटलॉग कैसे देखें?" if is_hi else "How to view catalogue?",
                ],
            )

        # 4. Off-topic general trivia, entertainment, crypto, politics
        trivia_patterns = [
            "who is the president",
            "who is the prime minister",
            "cricket score",
            "ipl match",
            "bitcoin price",
            "crypto",
            "stock tips",
            "weather forecast",
            "movie review",
            "medical diagnosis",
            "prescribe medicine",
            "who won the",
            "tell me a joke about animals",
        ]
        if any(p in clean for p in trivia_patterns):
            logger.warning("[Guardrail] Unrelated trivia/advice blocked: %s", clean[:60])
            return ChatResponseSchema(
                reply=(
                    "माफ़ कीजिए, मैं केवल कलासेतु ऐप, सरकारी योजनाओं और हस्तशिल्प से जुड़े सवालों के जवाब दे सकता हूँ। सामान्य जानकारी के लिए कृपया सर्च इंजन का उपयोग करें।"
                    if is_hi
                    else "I apologize, but I am dedicated exclusively to KalaSetu, artisan business, and handicraft guidance. For general queries, please consult a web search engine."
                ),
                action=None,
                suggested_queries=[
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How do I add a product?",
                    "मेरी कमाई और बिक्री दिखाएं" if is_hi else "Show my earnings & stats",
                ],
            )

        return None

    def _parse_llm_response(
        self,
        data: Dict[str, Any],
        user_msg: str,
        app_lang: str,
        artisan_craft: Optional[str] = None,
    ) -> ChatResponseSchema:
        """Parse and sanitize LLM response dict into ChatResponseSchema with strict asterisk elimination."""
        raw_reply = data.get("reply", "").strip() or "Namaste! I am here to help you."

        # Completely eliminate all asterisks (*) and normalize spaces
        reply = re.sub(r'\*+', '', raw_reply)
        reply = re.sub(r'[ \t]+', ' ', reply).strip()

        action_data = data.get("action")
        action: Optional[ChatActionSchema] = None

        if isinstance(action_data, dict) and action_data.get("type"):
            act_type = action_data.get("type", "navigate")
            destination = action_data.get("destination") or "catalogue"
            route = action_data.get("route")
            tab_index = action_data.get("tab_index")
            raw_label = action_data.get("label") or f"Go to {destination.replace('_', ' ').title()}"
            label = re.sub(r'\*+', '', raw_label).strip()
            params = action_data.get("params")

            action = ChatActionSchema(
                type=act_type,
                destination=destination,
                route=route,
                tab_index=tab_index,
                label=label,
                params=params,
            )

        # If LLM didn't emit an action, check if user message had a deterministic action command
        if action is None:
            fallback = self._rule_based_fallback(user_msg, app_lang, artisan_craft=artisan_craft)
            if fallback.action is not None:
                action = fallback.action

        # Ensure language mismatch suggestion is present if query language differs from app_lang
        is_devanagari = bool(re.search(r'[\u0900-\u097F]', user_msg))
        is_query_hindi = is_devanagari or any(
            w in user_msg.lower().split()
            for w in ["kaise", "kahan", "kya", "mera", "meri", "apna", "apni", "batao", "karo", "saman", "bechna", "jodna", "hai", "hain", "keemat", "mulya", "sujhav"]
        )
        is_lang_mismatch = (app_lang == "en" and is_query_hindi) or (app_lang == "hi" and not is_query_hindi and not is_devanagari)

        if is_lang_mismatch:
            has_suggestion = any(
                phrase in reply.lower()
                for phrase in [
                    "भाषा सेटिंग्स", "language settings", "सुझाव:", "suggestion:", "bhasha", "language page"
                ]
            )
            if not has_suggestion:
                if is_query_hindi:
                    reply = "सुझाव: यदि आप कलासेतु ऐप की भाषा हिंदी में बदलना चाहते हैं, तो आप भाषा सेटिंग्स में जाकर इसे बदल सकते हैं।\n\n" + reply
                else:
                    reply = "Suggestion: If you prefer using KalaSetu in English, you can switch the app language in Language Settings.\n\n" + reply

            # If no action was set or action is generic, provide navigation to language_settings
            if action is None:
                action = ChatActionSchema(
                    type="navigate",
                    destination="language_settings",
                    route="/language-settings",
                    tab_index=None,
                    label="भाषा सेटिंग्स खोलें" if is_query_hindi else "Open Language Settings",
                    params={},
                )

        suggested = data.get("suggested_queries", [])
        if not isinstance(suggested, list) or not suggested:
            is_hi = is_query_hindi if is_lang_mismatch else (app_lang == "hi")
            craft_lower = (artisan_craft or "").lower()
            if "pottery" in craft_lower or "terracotta" in craft_lower or "clay" in craft_lower:
                suggested = [
                    "टेराकोटा में दरारें कैसे रोकें?" if is_hi else "How to avoid cracks in pottery?",
                    "कुम्हारों के लिए पीएम विश्वकर्मा" if is_hi else "PM Vishwakarma for potters",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ]
            elif "textile" in craft_lower or "handloom" in craft_lower or "weav" in craft_lower:
                suggested = [
                    "हथकरघा में धागे टूटने से कैसे बचाएं?" if is_hi else "How to prevent thread breaks in weaving?",
                    "बुनकरों के लिए सरकारी योजनाएं" if is_hi else "Govt schemes for handloom weavers",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ]
            elif "wood" in craft_lower or "carv" in craft_lower:
                suggested = [
                    "लकड़ी में दरार व मुड़ने से कैसे बचाएं?" if is_hi else "How to prevent wood warping and cracks?",
                    "बढ़ई वर्ग के लिए टूलकिट सहायता" if is_hi else "PM Vishwakarma for carpenters",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ]
            elif "metal" in craft_lower or "brass" in craft_lower or "dhokra" in craft_lower:
                suggested = [
                    "पीतल की चमक कैसे बनाए रखें?" if is_hi else "How to prevent tarnishing in brassware?",
                    "धातु शिल्पकारों के लिए योजनाएं" if is_hi else "Govt schemes for metalcraft artisans",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ]
            else:
                suggested = [
                    "नया उत्पाद कैसे जोड़ें?" if is_hi else "How to add a product?",
                    "पीएम विश्वकर्मा योजना क्या है?" if is_hi else "What is PM Vishwakarma scheme?",
                    "उचित मूल्य कैसे तय होता है?" if is_hi else "How does fair pricing work?",
                    "माय कैटलॉग खोलें" if is_hi else "Take me to my catalogue",
                ]

        clean_suggested = [re.sub(r'\*+', '', str(q)).strip() for q in suggested[:4]]

        return ChatResponseSchema(
            reply=reply,
            action=action,
            suggested_queries=clean_suggested,
        )

    def _rule_based_fallback(
        self,
        query: str,
        language_code: str,
        artisan_craft: Optional[str] = None,
    ) -> ChatResponseSchema:
        """
        Robust offline intent matching for artisan assistance, craft advice, schemes,
        and screen navigation. Always answers in the query language, suggests language
        settings on mismatch, produces zero asterisks, and tailors craft advice to the
        artisan's profile craft unless another craft is explicitly specified.
        """
        q = query.lower().strip()

        # Detect question language
        has_devanagari = bool(re.search(r'[\u0900-\u097F]', q))
        is_query_hindi = has_devanagari or any(
            w in q for w in [
                "kaise", "kahan", "batao", "mujhe", "kholo", "jana", "hai", "kya", "saman",
                "kamai", "bataiye", "kariye", "karo", "bikri", "karigar", "shilp", "yojana", "darar"
            ]
        )

        # Rule: Always answer in the same language in which query was asked
        is_hindi = is_query_hindi

        # Mismatch check between query language and app's selected language
        is_mismatch = (is_query_hindi and language_code != "hi") or (not is_query_hindi and language_code == "hi")
        if is_mismatch:
            if is_query_hindi:
                suggestion_prefix = "सुझाव: यदि आप कलासेतु ऐप की भाषा हिंदी में बदलना चाहते हैं, तो आप भाषा सेटिंग्स में जाकर इसे बदल सकते हैं।\n\n"
                default_action = ChatActionSchema(
                    type="navigate",
                    destination="language_settings",
                    route="/language-settings",
                    tab_index=None,
                    label="भाषा सेटिंग्स खोलें",
                    params={},
                )
            else:
                suggestion_prefix = "Suggestion: If you prefer using KalaSetu in English, you can switch the app language in Language Settings.\n\n"
                default_action = ChatActionSchema(
                    type="navigate",
                    destination="language_settings",
                    route="/language-settings",
                    tab_index=None,
                    label="Open Language Settings",
                    params={},
                )
        else:
            suggestion_prefix = ""
            default_action = None

        # ── Craft Taxonomy & Profile Resolution ────────────────────────────
        craft_taxa = {
            "pottery": {
                "keywords": ["pottery", "terracotta", "clay", "mitti", "kiln", "bhatti", "matka", "diya", "surahi", "ceramic", "glaze", "kumhar"],
                "name_en": "Terracotta Pottery",
                "name_hi": "टेराकोटा व मिट्टी शिल्प",
            },
            "textiles": {
                "keywords": ["handloom", "textile", "textiles", "weaving", "weaver", "bunkar", "loom", "saree", "dupatta", "fabric", "chanderi", "warp", "weft"],
                "name_en": "Handloom & Textiles",
                "name_hi": "हथकरघा व वस्त्र",
            },
            "woodwork": {
                "keywords": ["wood", "woodwork", "carving", "lakdi", "sheesham", "teak", "furniture", "chisel", "carpenter", "badhai", "suthar"],
                "name_en": "Woodwork & Carving",
                "name_hi": "काष्ठ नक्काशी व बढ़ईगीरी",
            },
            "metalcraft": {
                "keywords": ["metal", "brass", "brassware", "pital", "bronze", "dhokra", "dokra", "casting", "lohar", "blacksmith", "kasar", "tarnish"],
                "name_en": "Metalcraft & Brassware",
                "name_hi": "धातुशिल्प व पीतल कार्य",
            },
            "jewelry": {
                "keywords": ["jewelry", "jewellery", "gehna", "ornament", "beads", "tribal jewelry", "silver", "zari"],
                "name_en": "Handmade Jewelry",
                "name_hi": "हस्तनिर्मित आभूषण",
            },
            "painting": {
                "keywords": ["painting", "paintings", "madhubani", "warli", "pattachitra", "canvas", "art", "pigment", "chitra"],
                "name_en": "Folk Paintings & Art",
                "name_hi": "लोक चित्रकला",
            },
            "leather": {
                "keywords": ["leather", "jutti", "mojri", "chamra", "hide", "charmakar"],
                "name_en": "Leather & Jutti Craft",
                "name_hi": "चर्मशिल्प व जूती",
            },
            "bamboo": {
                "keywords": ["bamboo", "cane", "jute", "tokri", "baans"],
                "name_en": "Bamboo, Cane & Jute",
                "name_hi": "बांस, बेंत व जूट शिल्प",
            },
            "stone": {
                "keywords": ["stone", "patthar", "sculpture", "shila", "marble", "moorti", "moortikar"],
                "name_en": "Stone Carving",
                "name_hi": "प्रस्तर शिल्प व मूर्तिकला",
            },
        }

        # Determine profile domain
        profile_craft_raw = (artisan_craft or "").strip()
        profile_domain = None
        if profile_craft_raw:
            p_lower = profile_craft_raw.lower()
            for dom, info in craft_taxa.items():
                if any(kw in p_lower for kw in info["keywords"]):
                    profile_domain = dom
                    break

        # Check if user explicitly asked for another craft
        explicit_other_domain = None
        for dom, info in craft_taxa.items():
            if profile_domain and dom == profile_domain:
                continue
            distinctive_kws = [kw for kw in info["keywords"] if kw not in ["art", "glaze", "warp", "weft"]]
            if any(kw in q for kw in distinctive_kws):
                explicit_other_domain = dom
                break

        # Active craft domain: explicit craft if requested, otherwise profile craft
        active_domain = explicit_other_domain or profile_domain

        # ── Direct Action 1: Instant Sync Trigger ─────────────────────────
        if any(w in q for w in [
            "sync my pending", "sync pending", "sync offline", "sync now", "sync products",
            "upload offline", "upload pending", "pending sync", "offline sync", "sync karo"
        ]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + "ऑफ़लाइन लंबित उत्पादों का ऑनलाइन सिंक शुरू किया जा रहा है। प्रगति नीचे प्रदर्शित होगी...",
                    action=ChatActionSchema(
                        type="sync_pending",
                        destination="catalogue",
                        tab_index=1,
                        label="लंबित उत्पाद सिंक करें",
                        params={},
                    ),
                    suggested_queries=["माय कैटलॉग खोलें", "मेरी कमाई दिखाएं", "नया उत्पाद जोड़ें"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + "Initiating synchronization for your pending offline products. Progress will update below...",
                action=ChatActionSchema(
                    type="sync_pending",
                    destination="catalogue",
                    tab_index=1,
                    label="Sync Offline Products Now",
                    params={},
                ),
                suggested_queries=["Show my catalogue", "Show my stats", "Add new product"],
            )

        # ── Direct Action 2: Product Status Update (Sold / Live / Draft) ──
        has_status_action = False
        target = "product"
        target_status = "sold"

        if " as " in q and ("mark " in q or q.startswith("mark")):
            parts = q.split(" as ")
            if len(parts) >= 2:
                left = parts[0].strip()
                right_words = parts[1].strip().split()
                right = right_words[0].strip("?.,!;:") if right_words else ""
                if right in ["sold", "live", "draft"]:
                    left_words = left.split()
                    if left_words and left_words[0] == "mark":
                        left_words = left_words[1:]
                    if left_words and left_words[0] in ["my", "the", "this", "mera", "meri", "ye", "apna", "apni"]:
                        left_words = left_words[1:]
                    target = " ".join(left_words).strip() or "product"
                    target_status = right
                    has_status_action = True
        elif "bik gaya" in q or "बिक गया" in q:
            target = q.replace("bik gaya", "").replace("बिक गया", "").replace("mera", "").replace("meri", "").replace("ye", "").strip() or "product"
            target_status = "sold"
            has_status_action = True
        elif any(w in q for w in ["sold mark", "mark sold", "set sold", "mark as sold"]) or ("sold" in q and any(w in q for w in ["mark", "update", "set", "kar"])):
            target = "product"
            target_status = "sold"
            has_status_action = True

        if has_status_action:
            clean_target = target
            for prefix in ["my ", "the ", "this ", "mera ", "meri ", "ye ", "apna ", "apni "]:
                if clean_target.lower().startswith(prefix):
                    clean_target = clean_target[len(prefix):].strip()
                    break

            label_en = f"Mark as {target_status.capitalize()}"
            label_hi = "बिका हुआ चिह्नित करें" if target_status == "sold" else f"{target_status.capitalize()} करें"

            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + f"मैं आपके कैटलॉग में '{clean_target or 'उत्पाद'}' का स्टेटस '{target_status}' अपडेट कर रहा हूँ। आप इसे कभी भी नीचे अनडू (Undo) कर सकते हैं।",
                    action=ChatActionSchema(
                        type="update_product_status",
                        destination="catalogue",
                        tab_index=1,
                        label=label_hi,
                        params={
                            "target_product": clean_target or "product",
                            "status": target_status,
                        },
                    ),
                    suggested_queries=["माय कैटलॉग खोलें", "मेरी कमाई दिखाएं", "लंबित सिंक करें"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + f"Updating '{clean_target or 'product'}' in your catalogue to status '{target_status}'. You can undo this action anytime below.",
                action=ChatActionSchema(
                    type="update_product_status",
                    destination="catalogue",
                    tab_index=1,
                    label=label_en,
                    params={
                        "target_product": clean_target or "product",
                        "status": target_status,
                    },
                ),
                suggested_queries=["Show my catalogue", "Show my stats", "Sync pending items"],
            )

        # ── Direct Action 3: Pre-filtered Catalogue Navigation ────────────
        triggers = {"show", "filter", "find", "search", "dikhaye", "dikhao"}
        negatives = {"how", "kaise", "what", "kya", "add", "jodna", "mark", "sync"}
        filler_words = {"the", "all", "my", "me", "some", "please", "mere", "meri", "sab", "sabhi", "apna", "apni", "apne"}

        words = [w.strip("?.,!;:") for w in q.split()]
        if not any(w in negatives for w in words):
            trigger_idx = -1
            for idx, word in enumerate(words):
                if word in triggers:
                    trigger_idx = idx
                    break

            if trigger_idx != -1 and trigger_idx + 1 < len(words):
                tokens = words[trigger_idx + 1:]
                while len(tokens) > 1 and tokens[-1] in ["items", "products", "crafts", "catalogue", "catalog", "saman"]:
                    tokens.pop()
                if len(tokens) > 1 and tokens[-1] == "in":
                    tokens.pop()
                tokens = [tok for tok in tokens if tok not in filler_words]
                query_term = " ".join(tokens).strip()

                if query_term and query_term not in ["catalogue", "catalog", "products", "items", "saman", "crafts", "craft"]:
                    if is_hindi:
                        return ChatResponseSchema(
                            reply=suggestion_prefix + f"कैटलॉग में '{query_term}' से संबंधित आपके आइटम फ़िल्टर करके दिखाए जा रहे हैं।",
                            action=ChatActionSchema(
                                type="filter_catalogue",
                                destination="catalogue",
                                tab_index=1,
                                label=f"कैटलॉग में '{query_term}' देखें",
                                params={
                                    "query": query_term,
                                    "category": None,
                                },
                            ),
                            suggested_queries=["नया सामान जोड़ें", "मेरी कमाई दिखाएं", "लंबित सिंक करें"],
                        )
                    return ChatResponseSchema(
                        reply=suggestion_prefix + f"Navigating to your catalogue pre-filtered for '{query_term}'.",
                        action=ChatActionSchema(
                            type="filter_catalogue",
                            destination="catalogue",
                            tab_index=1,
                            label=f"Show '{query_term}' in Catalogue",
                            params={
                                "query": query_term,
                                "category": None,
                            },
                        ),
                        suggested_queries=["Add new product", "Show my stats", "Sync pending items"],
                    )

        # Intent: Government Schemes (PM Vishwakarma, Mudra, Pehchan)
        if any(w in q for w in ["vishwakarma", "mudra", "pehchan", "yojana", "scheme", "subsidy", "anudan", "sarkari"]):
            # Craft-specific note for PM Vishwakarma trade
            trade_note_hi = ""
            trade_note_en = ""
            if active_domain == "pottery":
                trade_note_hi = "\n• आपके शिल्प (कुम्हार / Potter) के लिए: आधुनिक इलेक्ट्रिक चाक (Motorized Potter Wheel), सांचे और ₹15,000 टूलकिट सहायता।"
                trade_note_en = "\n• For your craft trade (Kumhar / Potter): Modern motorized potter's wheel, clay processing tools, and Rs 15,000 toolkit incentive."
            elif active_domain == "textiles":
                trade_note_hi = "\n• आपके शिल्प (बुनकर / Weaver) के लिए: उन्नत हथकरघा सहायक उपकरण, ताना-बाना रील्स और ₹15,000 टूलकिट सहायता।"
                trade_note_en = "\n• For your craft trade (Weaver / Artisan): Advanced loom accessories, warping frames, and Rs 15,000 toolkit incentive."
            elif active_domain == "woodwork":
                trade_note_hi = "\n• आपके शिल्प (सुथार / बढ़ई) के लिए: आधुनिक इलेक्ट्रिक रंदा, राउटर, छेनी सेट और ₹15,000 टूलकिट सहायता।"
                trade_note_en = "\n• For your craft trade (Suthar / Carpenter): Electric planer, router, precision chisel sets, and Rs 15,000 toolkit incentive."
            elif active_domain == "metalcraft":
                trade_note_hi = "\n• आपके शिल्प (लोहार / कसेरा / धातुशिल्पी) के लिए: उन्नत भट्ठी ब्लोअर, निहाई, पॉलिशिंग किट और ₹15,000 टूलकिट सहायता।"
                trade_note_en = "\n• For your craft trade (Blacksmith / Bronze Artisan): Kiln blowers, anvils, buffing kits, and Rs 15,000 toolkit incentive."

            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "कारीगरों के लिए मुख्य सरकारी योजनाएं और वित्तीय सहायता:\n\n"
                        "1. पीएम विश्वकर्मा योजना (PM Vishwakarma):\n"
                        "• ₹15,000 का आधुनिक टूलकिट प्रोत्साहन।"
                        f"{trade_note_hi}\n"
                        "• बिना किसी गारंटी के मात्र 5% रियायती ब्याज पर ₹3 लाख तक का उद्यम ऋण (पहली किस्त ₹1 लाख, दूसरी ₹2 लाख)।\n"
                        "• बुनियादी व उन्नत कौशल प्रशिक्षण और प्रशिक्षण के दौरान ₹500 प्रतिदिन का वज़ीफ़ा।\n"
                        "• राष्ट्रीय स्तर पर उत्पादों की मार्केटिंग और ब्रांडिंग सहायता।\n\n"
                        "2. पहचान कार्ड (Pehchan Artisan Card):\n"
                        "• वस्त्र मंत्रालय द्वारा जारी आधिकारिक पहचान पत्र।\n"
                        "• दिल्ली हाट, सूरजकुंड जैसे राष्ट्रीय शिल्पोत्सवों में सीधे स्टॉल पाने की पात्रता।\n"
                        "• कारीगर बीमा और रियायती रेल यात्रा की सुविधा।\n\n"
                        "3. मुद्रा योजना (MUDRA Loan):\n"
                        "• शिशु ऋण: ₹50,000 तक कच्चा माल खरीदने के लिए।\n"
                        "• किशोर ऋण: ₹50,000 से ₹5 लाख तक उपकरण और कार्यशाला विस्तार के लिए।"
                    ),
                    action=default_action,
                    suggested_queries=[
                        "शिल्प सुधार के सुझाव",
                        "उचित मूल्य कैसे तय करें?",
                        "नया उत्पाद जोड़ें",
                    ],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + (
                    "Key Government Schemes & Financial Support for Indian Artisans:\n\n"
                    "1. PM Vishwakarma Scheme:\n"
                    "• Modern toolkit incentive of Rs 15,000."
                    f"{trade_note_en}\n"
                    "• Collateral-free enterprise credit up to Rs 3 Lakh at subsidized 5% interest rate (Tranche 1: Rs 1 Lakh, Tranche 2: Rs 2 Lakh).\n"
                    "• Free skill training with a Rs 500 daily stipend.\n"
                    "• Nationwide marketing linkages and digital transaction incentives.\n\n"
                    "2. Pehchan Artisan ID Card:\n"
                    "• Official identity card from the Ministry of Textiles.\n"
                    "• Direct eligibility to exhibit and sell at national craft haats (Dilli Haat, Surajkund, etc.).\n"
                    "• Subsidized health insurance and railway travel concessions.\n\n"
                    "3. MUDRA Loan Scheme:\n"
                    "• Shishu Loan: Up to Rs 50,000 for raw material working capital.\n"
                    "• Kishore Loan: Rs 50,000 to Rs 5 Lakh for workshop equipment and scaling production."
                ),
                action=default_action,
                suggested_queries=[
                    "How to improve craft quality?",
                    "How does fair pricing work?",
                    "Add new product",
                ],
            )

        # Intent: Craft Improvement, Quality, Defects, Raw Materials & Techniques
        if any(w in q for w in [
            "improve", "quality", "technique", "glaze", "kiln", "bhatti", "crack", "dye",
            "packaging", "darar", "tikau", "humidity", "weather", "dry", "drying", "sukha",
            "source", "sourcing", "raw material", "kaccha", "clay", "mitti", "lakdi", "brass",
            "pital", "loha", "chanderi", "saree", "dhokra", "bunkar", "wood", "seasoning", "chamak"
        ]):
            if active_domain == "pottery":
                if is_hindi:
                    return ChatResponseSchema(
                        reply=suggestion_prefix + (
                            "टेराकोटा व मिट्टी शिल्प (Terracotta & Pottery) की गुणवत्ता और तकनीक सुधार के सुझाव:\n\n"
                            "1. दरार रोकने व सुखाने की विधि: गीली मिट्टी के बर्तनों को कभी भी सीधी तेज़ धूप में न सुखाएं। हमेशा छायादार जगह में धीरे-धीरे (Slow Air Drying) सूखने दें ताकि सतह और अंदरूनी हिस्से में एकसमान नमी रहे और दरारें न आएं।\n"
                            "2. मिट्टी की तैयारी (Levigation & Wedging): मिट्टी को पानी में घोलकर बारीक छानें ताकि कंकड़ और रेत अलग हो जाएं। मिट्टी को अच्छी तरह गूंथें (Wedge) ताकि हवा के बुलबुले निकल जाएं।\n"
                            "3. भट्ठी (Kiln) पकाई: भट्ठी का तापमान धीरे-धीरे बढ़ाएं ताकि रासायनिक नमी धीरे-धीरे निकले। पकाने के बाद भट्ठी को तुरंत न खोलें, इसे 12-16 घंटे प्राकृतिक रूप से ठंडा होने दें।\n"
                            "4. कच्चा माल व पैकेजिंग: चिकनी नदी की गाद (River silt clay) या माटी कला बोर्ड केंद्रों से शुद्ध मिट्टी लें। कूरियर शिपिंग के लिए हनीकॉम्ब पेपर पैडिंग और डबल-वॉल बॉक्स का उपयोग करें।"
                        ),
                        action=default_action,
                        suggested_queries=["कुम्हारों के लिए पीएम विश्वकर्मा", "उचित मूल्य कैसे तय करें?", "नया उत्पाद जोड़ें"],
                    )
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "Quality & Technique Improvement for Terracotta & Pottery:\n\n"
                        "1. Preventing Cracks & Slow Drying: Never dry freshly shaped terracotta items in direct harsh sunlight. Always slow-dry in the shade so internal and surface moisture evaporate uniformly without causing hairline fractures.\n"
                        "2. Clay Preparation & Wedging: Thoroughly levigate and sieve clay to eliminate grit and organic impurities. Wedge clay vigorously to remove all trapped air pockets before throwing.\n"
                        "3. Kiln Firing & Cooling: Ramp up kiln temperature gradually to allow chemical moisture to escape gently. After firing, allow the kiln to cool naturally over 12-16 hours before opening.\n"
                        "4. Sourcing & Transit Packaging: Source fine river silt clay from certified craft clusters or local riverbeds. For shipping, wrap fragile pottery in biodegradable honeycomb paper and double-wall corrugated boxes with edge protectors."
                    ),
                    action=default_action,
                    suggested_queries=["PM Vishwakarma for potters", "How does fair pricing work?", "Add new product"],
                )

            elif active_domain == "textiles":
                if is_hindi:
                    return ChatResponseSchema(
                        reply=suggestion_prefix + (
                            "हथकरघा व वस्त्र शिल्प (Handloom & Textiles) की गुणवत्ता सुधार के सुझाव:\n\n"
                            "1. ताने का खिंचाव (Warp Tension): करघे पर ताने का खिंचाव एकसमान रखें। असमान खिंचाव से धागा बार-बार टूटता है और कपड़े के किनारों (Selvedge) में सिकुड़न आती है।\n"
                            "2. प्राकृतिक रंग व पक्कापन: नील (Indigo), मजीठ या हल्दी से रंगाई में फिटकरी (Alum) या हरड़ का सही अनुपात उपयोग करें ताकि रंग धोने व धूप में न उड़े।\n"
                            "3. धागे की गुणवत्ता व सोर्सिंग: राष्ट्रीय हथकरघा विकास निगम (NHDC) या बुनकर सेवा केंद्रों से प्रमाणित सूती व रेशमी धागा प्राप्त करें।\n"
                            "4. पैकेजिंग व सुरक्षा: कपड़ों को नमी व फफूंद से बचाने के लिए बटर पेपर और वाटरप्रूफ इनर पैकिंग में सिलिका जेल के साथ पैक करें।"
                        ),
                        action=default_action,
                        suggested_queries=["बुनकरों के लिए सरकारी योजनाएं", "उचित मूल्य कैसे तय करें?", "नया उत्पाद जोड़ें"],
                    )
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "Quality & Technique Improvement for Handloom & Textiles:\n\n"
                        "1. Warp Tension & Breakage Prevention: Maintain uniform loom tension across all warp ends. Uneven tension causes frequent thread breakage, rippling, and wavy selvedge margins.\n"
                        "2. Natural Dye Colorfastness: Use authentic mineral mordants (alum, iron water, harda) with vegetable dyes like indigo and madder so colors remain wash-fast and sun-fast.\n"
                        "3. Yarn Sourcing: Procure certified organic cotton and mulberry silk yarn from National Handloom Development Corporation (NHDC) depots or Weavers' Service Centres.\n"
                        "4. Moisture-Proof Packaging: Fold textiles in acid-free tissue paper with a waterproof layer and silica gel packs to prevent dampness and mildew during transit."
                    ),
                    action=default_action,
                    suggested_queries=["Govt schemes for handloom weavers", "How does fair pricing work?", "Add new product"],
                )

            elif active_domain == "woodwork":
                if is_hindi:
                    return ChatResponseSchema(
                        reply=suggestion_prefix + (
                            "काष्ठ नक्काशी व काष्ठशिल्प (Woodwork & Carving) की गुणवत्ता सुधार के सुझाव:\n\n"
                            "1. लकड़ी की सीज़निंग (Seasoning): गीली लकड़ी पर नक्काशी न करें। हमेशा 8-12% नमी वाली भट्ठी में सुखाई गई (Kiln-seasoned) शीशम, सागौन या अखरोट की लकड़ी चुनें ताकि मुड़ने और दरार से बचाव हो।\n"
                            "2. दीमक व कीड़ों से सुरक्षा: नक्काशी से पहले पर्यावरण-अनुकूल बोरेट या नीम तेल से एंटी-टर्माइट उपचार करें।\n"
                            "3. औज़ारों की धार: अपनी छेनी और रुखानी (Chisels) को हमेशा ऑयलस्टोन पर तेज़ रखें ताकि नक्काशी के रेशे साफ और चिकने कटें।\n"
                            "4. प्राकृतिक फिनिशिंग: प्राकृतिक मधुमक्खी मोम (Beeswax) या अलसी के तेल (Linseed oil) से पॉलिश करें जो लकड़ी की प्राकृतिक सुंदरता को निखारती है।"
                        ),
                        action=default_action,
                        suggested_queries=["बढ़ई वर्ग के लिए टूलकिट सहायता", "उचित मूल्य कैसे तय करें?", "नया उत्पाद जोड़ें"],
                    )
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "Quality & Technique Improvement for Woodwork & Carving:\n\n"
                        "1. Wood Seasoning & Moisture Control: Never carve unseasoned timber. Use wood seasoned to 8-12% moisture content (sheesham, teak, walnut) to completely prevent warping and seasonal splitting.\n"
                        "2. Termite & Pest Protection: Treat lumber with eco-friendly borate or neem-based anti-borer solutions before detailed relief work.\n"
                        "3. Tool Maintenance: Keep your gouges and chisels razor-sharp using fine-grit sharpening stones; dull tools tear wood grain and ruin fine cuts.\n"
                        "4. Natural Finishing: Hand-rub surfaces with pure beeswax polish or boiled linseed oil to accentuate natural grain and resist moisture stains."
                    ),
                    action=default_action,
                    suggested_queries=["PM Vishwakarma for carpenters", "How does fair pricing work?", "Add new product"],
                )

            elif active_domain == "metalcraft":
                if is_hindi:
                    return ChatResponseSchema(
                        reply=suggestion_prefix + (
                            "धातुशिल्प व पीतल कार्य (Metalcraft & Brassware) की गुणवत्ता सुधार के सुझाव:\n\n"
                            "1. ढलाई व सांचे की तैयारी (Casting): ढोकरा या पीतल ढलाई में मिट्टी के सांचे को पिघली धातु डालने से पहले गर्म करें ताकि हवा के बुलबुले (Air bubbles) और छिद्र न बनें।\n"
                            "2. ऑक्सीकरण व कालेपन से बचाव: तैयार पीतल और कांसे के उत्पादों पर माइक्रोक्रिस्टलाइन मोम या पारदर्शी प्रोटेक्टिव लैकर की परत लगाएं ताकि नमी से धातु काली न पड़े।\n"
                            "3. मोम नक्काशी की शुद्धता: मधुमक्खी मोम की नक्काशी पर नदी की सबसे बारीक चिकनी मिट्टी का पहला लेप लगाएं जिससे सूक्ष्म डिज़ाइन स्पष्ट उभरें।\n"
                            "4. सफाई व पॉलिशिंग: प्राकृतिक इमली के घोल से सफाई के बाद पानी से धोकर सुखाएं और मुलायम कपड़े से बफिंग करें।"
                        ),
                        action=default_action,
                        suggested_queries=["धातु शिल्पकारों के लिए योजनाएं", "उचित मूल्य कैसे तय करें?", "नया उत्पाद जोड़ें"],
                    )
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "Quality & Technique Improvement for Metalcraft & Brassware:\n\n"
                        "1. Casting Precision: In lost-wax (Dhokra) or sand casting, thoroughly preheat molds before pouring molten brass or bronze to avoid cold shuts, air pockets, and porosity.\n"
                        "2. Tarnish & Oxidation Protection: Apply micro-crystalline wax or food-grade transparent protective lacquer to prevent ambient moisture from tarnishing polished brass.\n"
                        "3. Fine Detailing: Coat beeswax designs with ultra-fine river silt slip as the innermost layer to capture intricate decorative relief.\n"
                        "4. Finishing & Buffing: Clean with mild tamarind solution, neutralize thoroughly with clean water, and buff using a soft felt wheel."
                    ),
                    action=default_action,
                    suggested_queries=["Govt schemes for metalcraft artisans", "How does fair pricing work?", "Add new product"],
                )

            else:
                if is_hindi:
                    return ChatResponseSchema(
                        reply=suggestion_prefix + (
                            "शिल्प की गुणवत्ता और डिज़ाइन में सुधार के व्यावहारिक सुझाव:\n\n"
                            "1. कच्चा माल व तैयारी: मिट्टी को सही ढंग से छानकर कंकड़ निकालें। टेराकोटा में दरार रोकने के लिए भट्ठी का तापमान धीरे-धीरे बढ़ाएं और पकाने के बाद धीरे-धीरे ठंडा होने दें।\n"
                            "2. प्राकृतिक रंग व चमक: वनस्पति रंगों (नील, हरड़, मजीठ) में फिटकरी या गोंद का सही अनुपात मिलाएं ताकि रंग पक्का रहे और धूप में न उड़े।\n"
                            "3. आधुनिक डिज़ाइन का तालमेल: पारंपरिक रूपांकनों को बनाए रखते हुए आधुनिक शहरी उपयोग के उत्पाद (जैसे कुल्हड़ सेट, मिनिमल टेबलवेयर, लैपटॉप स्लीव, वॉल हैंगिंग) बनाएं।\n"
                            "4. सुरक्षित पैकेजिंग: कूरियर में सामान टूटने से बचाने के लिए डबल-वॉल कोरोगेटेड बॉक्स, बटर पेपर और पर्यावरण-अनुकूल हनीकॉम्ब पैडिंग का उपयोग करें।"
                        ),
                        action=default_action,
                        suggested_queries=["सरकारी योजनाएं बताएं", "बाज़ार के रुझान क्या हैं?", "नया उत्पाद जोड़ें"],
                    )
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "Practical Craft Quality & Design Improvement Advice:\n\n"
                        "1. Raw Materials & Preparation: Ensure clay is thoroughly levigated to remove grit. To avoid cracks in terracotta, heat kilns gradually and allow cooling slowly over 12-16 hours.\n"
                        "2. Natural Dyes & Colorfastness: Use authentic mordants (alum, iron water) with vegetable dyes (indigo, madder) to ensure colors remain vibrant after washing.\n"
                        "3. Modern Design Appeal: Retain your ancestral heritage motifs while creating functional products preferred by urban buyers (minimalist tableware, studio pottery, handloom laptop sleeves, contemporary wall hangings).\n"
                        "4. Safe Transit Packaging: To protect delicate crafts during shipping, wrap with biodegradable honeycomb paper or recycled corrugated boxes with edge protectors."
                    ),
                    action=default_action,
                    suggested_queries=["Explain govt schemes", "What are market trends?", "Add new product"],
                )

        # Intent: Market Trends, Melas & Haats
        if any(w in q for w in ["market", "bazar", "mela", "haat", "surajkund", "dilli haat", "saras", "hunar", "trend", "export", "gi tag"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "हस्तशिल्प बाज़ार के ताज़ा रुझान और प्रमुख मेले:\n\n"
                        "1. वर्तमान बाज़ार मांग:\n"
                        "• प्राकृतिक और पर्यावरण-अनुकूल उत्पादों की शहरी खरीदारों में भारी मांग है (प्लास्टिक-मुक्त बर्तन, जैविक सूती व रेशमी वस्त्र)।\n"
                        "• प्रामाणिक हस्तनिर्मित उत्पादों के साथ कारीगर की कहानी (Story of Origin) खरीदारों को बहुत आकर्षित करती है।\n\n"
                        "2. शीर्ष राष्ट्रीय मेले व प्रदर्शनियां:\n"
                        "• सूरजकुंड अंतरराष्ट्रीय शिल्प मेला (फरीदाबाद, हरियाणा - प्रतिवर्ष फरवरी)।\n"
                        "• दिल्ली हाट (आईएनए, दिल्ली - सालभर बदलते शिल्पी स्टॉल)।\n"
                        "• सरस आजीविका मेला (SARAS) और हुनर हाट (Hunar Haat)।\n"
                        "• गांधी शिल्प बाज़ार (देशभर के प्रमुख शहरों में वस्त्र मंत्रालय द्वारा आयोजित)।\n\n"
                        "3. जीआई टैग (GI Tag) लाभ: अपने क्षेत्र के पंजीकृत जीआई शिल्प की प्रामाणिकता दिखाकर आप 20% से 30% अधिक मूल्य प्राप्त कर सकते हैं।"
                    ),
                    action=default_action,
                    suggested_queries=["पीएम विश्वकर्मा योजना", "उचित मूल्य कैसे तय करें?", "माय कैटलॉग खोलें"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + (
                    "Handicraft Market Trends & Top Craft Exhibitions:\n\n"
                    "1. Current Market Trends:\n"
                    "• High demand among urban buyers for sustainable, eco-friendly lifestyle crafts (terracotta dinnerware, organic handloom textiles, carved wooden organizers).\n"
                    "• Products that showcase the artisan's personal story and cluster heritage command 25% to 40% higher customer value online.\n\n"
                    "2. Top National Exhibitions & Haats:\n"
                    "• Surajkund International Crafts Mela (Faridabad, Haryana - every February).\n"
                    "• Dilli Haat (INA, New Delhi - rotating fortnightly artisan stalls).\n"
                    "• SARAS Aajeevika Mela & Hunar Haat.\n"
                    "• Gandhi Shilp Bazaar (organized nationwide by the Development Commissioner of Handicrafts).\n\n"
                    "3. Geographical Indication (GI Tag): Highlighting official GI certification protects regional authenticity and commands premium export pricing."
                ),
                action=default_action,
                suggested_queries=["Govt schemes for artisans", "How does pricing work?", "Open my catalogue"],
            )

        # Intent: Add Product
        if any(w in q for w in ["add product", "add a product", "add new product", "naya saman", "upload", "bechna", "list", "jodna", "create product", "photo"]) or ("add" in q and ("product" in q or "item" in q or "craft" in q or "saman" in q)):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "आप अपने हस्तशिल्प उत्पाद को केवल 5 आसान चरणों में जोड़ सकते हैं:\n"
                        "1. फ़ोटो खींचें (AI इसे बेहतर बनाएगा)\n"
                        "2. बोलकर उत्पाद का विवरण दें\n"
                        "3. विवरण व टैग की समीक्षा करें\n"
                        "4. पारदर्शी मूल्य (सामग्री + मेहनत) तय करें\n"
                        "5. कैटलॉग में प्रकाशित करें।"
                    ),
                    action=ChatActionSchema(
                        type="navigate",
                        destination="add_product",
                        route="/add-product",
                        tab_index=0,
                        label="उत्पाद जोड़ें पर जाएं",
                    ),
                    suggested_queries=["कीमत कैसे तय होती है?", "कैटलॉग दिखाएं", "ऑफ़लाइन मोड क्या है?"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + (
                    "You can add a product in 5 simple steps:\n"
                    "1. Take product photos (AI enhances them into studio quality)\n"
                    "2. Speak your craft description in your own language\n"
                    "3. Review AI-generated titles and craft tags\n"
                    "4. Evaluate fair pricing (material cost + labor hours)\n"
                    "5. Publish directly to your catalogue."
                ),
                action=ChatActionSchema(
                    type="navigate",
                    destination="add_product",
                    route="/add-product",
                    tab_index=0,
                    label="Go to Add Product",
                ),
                suggested_queries=["How does fair pricing work?", "Open my catalogue", "Can I work offline?"],
            )

        # Intent: Catalogue
        if any(w in q for w in ["catalogue", "catalog", "my items", "inventory", "stock", "mera saman", "list of products"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + "आपके सभी जोड़े गए उत्पाद और उनकी लाइव स्थिति 'माय कैटलॉग' स्क्रीन पर उपलब्ध हैं।",
                    action=ChatActionSchema(
                        type="navigate",
                        destination="catalogue",
                        route="/catalogue",
                        tab_index=1,
                        label="माय कैटलॉग खोलें",
                    ),
                    suggested_queries=["नया सामान जोड़ें", "मेरी कमाई दिखाएं", "कीमत कैसे तय करें?"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + "You can view, search, and manage all your craft listings and their sync status in the Catalogue screen.",
                action=ChatActionSchema(
                    type="navigate",
                    destination="catalogue",
                    route="/catalogue",
                    tab_index=1,
                    label="Open My Catalogue",
                ),
                suggested_queries=["Add new product", "Show my stats", "How does pricing work?"],
            )

        # Intent: Stats / Earnings
        if any(w in q for w in ["stats", "earnings", "kamai", "revenue", "sales", "bikri", "analytics", "income"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + "आप 'माय स्टैट्स' में जाकर अपनी कुल बिक्री, बिके हुए सामान की कमाई और शीर्ष क्राफ्ट श्रेणियों का विश्लेषण देख सकते हैं।",
                    action=ChatActionSchema(
                        type="navigate",
                        destination="my_stats",
                        route="/my-stats",
                        tab_index=None,
                        label="माय स्टैट्स खोलें",
                    ),
                    suggested_queries=["कैटलॉग दिखाएं", "नया उत्पाद जोड़ें", "भाषा बदलें"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + "Your sales revenue, total products listed, sold items, and top performing crafts are tracked in My Stats.",
                action=ChatActionSchema(
                    type="navigate",
                    destination="my_stats",
                    route="/my-stats",
                    tab_index=None,
                    label="Open My Stats",
                ),
                suggested_queries=["Show my catalogue", "How does fair pricing work?", "Add new product"],
            )

        # Intent: Pricing Explanation
        if any(w in q for w in ["pricing", "price", "kimat", "keemat", "rate", "cost", "floor price", "fair price"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "कलासेतु का उचित मूल्य निर्धारण (Fair Pricing Engine) यह सुनिश्चित करता है कि आपकी मेहनत की पूरी कीमत मिले:\n\n"
                        "• लागत तल (Floor Price) = कच्चा माल + (श्रम घंटे × प्रति घंटा मजदूरी)\n"
                        "• बाज़ार मूल्य: ई-कॉमर्स बाज़ार के आधार पर आपको एक उचित मूल्य दायरा सुझाया जाता है ताकि आप कभी घाटे में न बेचें।"
                    ),
                    action=ChatActionSchema(
                        type="navigate",
                        destination="add_product",
                        route="/add-product",
                        tab_index=0,
                        label="उत्पाद जोड़कर मूल्य देखें",
                    ),
                    suggested_queries=["उत्पाद कैसे जोड़ें?", "माय स्टैट्स दिखाएं", "ऑफ़लाइन काम कैसे करता है?"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + (
                    "KalaSetu's Fair Pricing Engine ensures you are never underpaid for your artisanal work:\n\n"
                    "• Cost Floor = Raw Materials + (Labor Hours × Fair Hourly Wage)\n"
                    "• Market Benchmark: Analyzes similar authentic handicrafts across e-commerce platforms to recommend a fair selling range.\n"
                    "• You always maintain complete control over the final price!"
                ),
                action=ChatActionSchema(
                    type="navigate",
                    destination="add_product",
                    route="/add-product",
                    tab_index=0,
                    label="Calculate Price for New Item",
                ),
                suggested_queries=["How to add a product?", "Open my stats", "Can I work offline?"],
            )

        # Intent: Language Settings
        if any(w in q for w in ["language", "bhasha", "hindi", "tamil", "bengali", "english", "change language"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply="आप ऐप की भाषा कभी भी सेटिंग्स में जाकर हिंदी, अंग्रेज़ी, तमिल या बांग्ला में बदल सकते हैं।",
                    action=ChatActionSchema(
                        type="navigate",
                        destination="language_settings",
                        route="/language-settings",
                        tab_index=None,
                        label="भाषा सेटिंग्स खोलें",
                    ),
                    suggested_queries=["कैटलॉग दिखाएं", "नया उत्पाद जोड़ें"],
                )
            return ChatResponseSchema(
                reply="You can switch the app language between English, Hindi, Tamil, and Bengali from Language Settings.",
                action=ChatActionSchema(
                    type="navigate",
                    destination="language_settings",
                    route="/language-settings",
                    tab_index=None,
                    label="Open Language Settings",
                ),
                suggested_queries=["How to add a product?", "Show my stats"],
            )

        # Intent: Profile
        if any(w in q for w in ["profile", "account", "mera profile", "details", "pehchan", "cluster"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + "आप अपनी प्रोफ़ाइल में अपना नाम, क्राफ्ट क्लस्टर, पहचान कार्ड आईडी और एनजीओ पार्टनर विवरण देख सकते हैं।",
                    action=ChatActionSchema(
                        type="navigate",
                        destination="profile",
                        route="/profile",
                        tab_index=3,
                        label="मेरी प्रोफ़ाइल खोलें",
                    ),
                    suggested_queries=["माय स्टैट्स खोलें", "कैटलॉग देखें"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + "You can manage your artisan name, craft cluster, Pehchan card number, and NGO partnership in your Profile.",
                action=ChatActionSchema(
                    type="navigate",
                    destination="profile",
                    route="/profile",
                    tab_index=3,
                    label="Open Profile",
                ),
                suggested_queries=["Show my stats", "Show my catalogue"],
            )

        # Intent: Offline Mode
        if any(w in q for w in ["offline", "internet", "net nahi", "bina internet", "sync"]):
            if is_hindi:
                return ChatResponseSchema(
                    reply=suggestion_prefix + (
                        "कलासेतु पूरी तरह ऑफ़लाइन भी काम करता है! आप बिना इंटरनेट के भी फ़ोटो ले सकते हैं और ऑडियो रिकॉर्ड कर सकते हैं।\n"
                        "जब भी फ़ोन इंटरनेट से जुड़ेगा, सभी उत्पाद स्वतः ही ऑनलाइन सर्वर पर सिंक हो जाएंगे।"
                    ),
                    action=default_action,
                    suggested_queries=["नया सामान जोड़ें", "कैटलॉग देखें", "मूल्य निर्धारण कैसे होता है?"],
                )
            return ChatResponseSchema(
                reply=suggestion_prefix + (
                    "KalaSetu is built offline-first! You can take photos and record voice notes even with zero internet connectivity.\n"
                    "All pending items are queued locally on your phone and sync automatically once you are back online."
                ),
                action=default_action,
                suggested_queries=["How to add a product?", "Show my catalogue", "How does pricing work?"],
            )

        # Default Greeting / Help
        craft_mention_hi = f"आपकी पंजीकृत शिल्प श्रेणी '{profile_craft_raw}' है। " if profile_craft_raw else ""
        craft_mention_en = f"Your registered craft category is '{profile_craft_raw}'. " if profile_craft_raw else ""
        if is_hindi:
            return ChatResponseSchema(
                reply=suggestion_prefix + f"नमस्ते! मैं कला-मित्र (KalaMitra) हूँ, आपका शिल्प व बाज़ार सहायक। {craft_mention_hi}मैं ऐप नेविगेशन, शिल्प सुधार, सरकारी योजनाओं (विश्वकर्मा) और उचित मूल्य तय करने में आपकी सहायता कर सकता हूँ। आप क्या जानना चाहते हैं?",
                action=default_action,
                suggested_queries=["सरकारी योजनाएं बताएं", "शिल्प सुधार सुझाव", "नया उत्पाद कैसे जोड़ें?", "माय कैटलॉग खोलें"],
            )
        return ChatResponseSchema(
            reply=suggestion_prefix + f"Namaste! I am KalaMitra, your artisan assistant and guide. {craft_mention_en}I can help answer your questions about craft techniques, government schemes like PM Vishwakarma, fair pricing, market trends, or take you directly to any screen in the app. How can I help you?",
            action=default_action,
            suggested_queries=["Tell me about PM Vishwakarma", "How to improve my craft?", "How to add a product?", "Open my catalogue"],
        )

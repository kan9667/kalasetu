# Voice Pipeline

A standalone Python module that turns an artisan's spoken description of a product into clean, catalog-ready text.

Built for artisans who create handmade products (textiles, sarees, handicrafts, pottery, jewelry, woodwork, bamboo crafts) and need a professional product listing without typing, and often without reading.

---

## What It Does

Takes a voice recording of an artisan describing their product — in Hindi or a regional language, often code-mixed with English — and produces a transcript ready for cataloging.

The module stops at the transcript. Listing generation belongs to the backend catalog service, and read-back belongs to the mobile app.

```
Artisan says:      "yeh mitti ka phooldaan hai, chaak pe banaya, natural clay se"

Pipeline returns:  text_for_listing → handed to the backend catalog service
                   language_code    → hi
                   provider         → whisper
```

## Pipeline

```
Flutter App — Voice Recording (.m4a, saved to the offline queue)
    ↓
Input Validation (file exists, size and duration check)
    ↓
Craft Glossary Prompt (handicraft vocabulary offered to the recogniser)
    ↓
Speech-to-Text (Whisper, transcript in the source language)
    ↓
Transcript Check (reject empty or failed transcriptions)
    ↓
Transcript ready for cataloging
    ↓
Backend Catalog Service (generates the bilingual listing — not this module)
    ↓
Flutter App — Voice Read-Back (on-device TTS, artisan confirms)
```

The first and last steps belong to other parts of the system. This module owns
the middle: audio in, catalog-ready text out.

---

## Installation

### 1. Create a virtual environment

```bash
python -m venv venv
```

### 2. Activate it

**Windows:**
```bash
venv\Scripts\activate
```

**Linux/macOS:**
```bash
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

> **Note:** A Whisper API key must be set in the project root `.env` before the pipeline can run. Any OpenAI-compatible host works — set `WHISPER_BASE_URL` to match. Verify with `python run_pipeline.py status`, which prints whether the key was found.

---

## Usage

### Command Line

**Basic usage** (transcribe and prepare text for cataloging):
```bash
python run_pipeline.py process --audio input/voice-note.m4a
```

**Transcribe only** (check speech recognition in isolation):
```bash
python run_pipeline.py transcribe --audio input/voice-note.m4a
```

**With options:**
```bash
# Regional language instead of Hindi
python run_pipeline.py process --audio input/saree.m4a --language ta

# Category hint improves classification and glossary selection
python run_pipeline.py process --audio input/pot.m4a --category Pottery

# Write the result to a JSON file
python run_pipeline.py process --audio input/pot.m4a --out result.json

# Show each stage as it runs
python run_pipeline.py process --audio input/pot.m4a --verbose

# Check configuration and language routing
python run_pipeline.py status
```

---

## Configuration

All settings are in **`config.py`**. Key settings:

| Setting | Default | Description |
|---|---|---|
| `stt_provider` | `whisper` | Transcription backend to use |
| `whisper_model` | `whisper-large-v3` | Model requested from the endpoint |
| `whisper_base_url` | OpenAI | Any OpenAI-compatible transcription API |
| `default_language` | `hi` | Source language when none is given |
| `supported_languages` | 10 codes | Languages the pipeline accepts |
| `max_audio_duration_seconds` | 180 | Reject longer recordings before making a request |
| `stt_request_timeout` | 60 | Request timeout in seconds |
| `stt_retry_attempts` | 3 | Retries for a failed transcription |
| `glossary_terms_in_prompt` | 40 | Craft terms offered to the recogniser |

Supported languages: Hindi (`hi`), Tamil (`ta`), Bengali (`bn`), Marathi (`mr`), Telugu (`te`), Gujarati (`gu`), Kannada (`kn`), Malayalam (`ml`), Punjabi (`pa`), and Odia (`or`).

The backend is chosen by `stt_provider` and resolved through a registry in `transcription/runner.py`. Adding another transcriber means one class and one registry entry — no other module changes.

---

## Project Structure

```
voice_pipeline/
│
├── run_pipeline.py        ── Start here. The command-line tool.
├── config.py              ── All settings, credentials, language routing
├── models.py              ── The shape of the data at each stage
├── __init__.py            ── What other code imports from this module
├── requirements.txt
├── README.md
├── .gitattributes
│
├── transcription/         ── audio  →  text
│   ├── whisper_transcriber.py     calls the Whisper endpoint
│   ├── base_transcriber.py        the contract any transcriber must follow
│   └── runner.py                  picks which transcriber to use
│
├── orchestrator/          ── Runs the stages in order, handles failures
│   └── processor.py
│
├── glossary/              ── Craft words fed to the recogniser and the backend
│   └── craft_terms.py             Bandhani, Dhokra, Pattachitra, ...
│
├── tests/                 ── Offline test suite (no API key needed)
│   └── test_voice_pipeline.py
│
├── input/                 ── Put artisan recordings here
└── data/                  ── Runtime logs (gitignored)
```

**Reading it top to bottom:** `run_pipeline.py` calls `orchestrator/`, which calls
`transcription/`. `config.py` and `models.py` are used by everything. `glossary/`
is used at transcription time and also exposed for the backend's listing prompt.


---

## Running Tests

```bash
pip install pytest
python -m pytest tests/ -v
```

35 tests, all offline — no API key, no network, and no audio files needed. Recordings are synthesised with the standard library, so the suite passes on a fresh clone.

Covered: language routing, craft glossary ordering, fallback-transcript rejection, audio validation, format detection, backend selection, and the handoff contract.

---

## Dependencies

| Package | Purpose |
|---|---|
| `requests` | HTTP client for the Whisper transcription endpoint |
| `pydantic` | Structured data models for every pipeline stage |
| `pydantic-settings` | Environment-based configuration |
| `python-dotenv` | Loads credentials from `.env` |
| `mutagen` | Reads audio duration before making a request |

---

## Processing Stages Explained

### 1. Voice Recording
The Flutter app records the artisan's description as an `.m4a` file and writes it to a local offline queue. Recording works with no connectivity — the file waits on the device and uploads when signal returns, so the artisan is never blocked.

### 2. Input Validation
Checks that the audio file exists, is non-empty, and falls within the duration limit. Runs before any network call so a broken recording fails instantly instead of costing a request.

### 3. Craft Glossary Prompt
Whisper accepts a prompt that biases recognition toward expected vocabulary. The glossary in `glossary/craft_terms.py` is passed there, category-first, so pottery terms are offered for a pottery listing rather than being cut by the limit.

This is where *Dhokra* stops becoming "doctor" and *Chikankari* stops becoming "chicken curry". Speech models trained on news and broadcast audio have barely encountered these words, and since they are frequently the product name itself, that failure is expensive.

### 4. Speech-to-Text
Posts the recording to the configured Whisper endpoint with the source language and the glossary prompt. Failed requests are retried up to three times.

Whisper is multilingual by training, so code-mixed speech — an artisan saying *"yeh handmade pottery hai"* in one breath — survives better than it does under single-language models. It also accepts the `.m4a` the mobile client records, so no conversion step is needed.

### 5. Transcript Check
A failed transcription returns a transcript flagged as a fallback rather than raising. The processor checks that flag and aborts before anything downstream runs.

This matters more than it looks: a silent fallback that resembles a successful transcript produces a confident, well-formatted listing for a product the artisan never described, with no way to tell it apart from a real one.

### 6. Handoff
The transcript is returned as `text_for_listing`. The backend catalog service consumes it and generates the bilingual listing: title, description, category, and tags in both English and Hindi.

Listing generation is deliberately not implemented here. It already exists in `backend/services/catalog_service.py`, and duplicating it would mean two prompts and two schemas drifting apart. The glossary is also exposed via `build_prompt_hint()` so the catalog service can apply the same vocabulary to its own prompt.

### 7. Voice Read-Back
The Flutter app speaks the generated listing back to the artisan using the phone's built-in speech engine, and they confirm or re-record.

This is the correctness gate. Many artisans cannot read the draft, so hearing it is the only way they can verify what was written about their product. Text-to-speech is deliberately absent from this module — it runs on the device so it works with no connectivity and no server call.

---

## Troubleshooting

### `status` reports credentials MISSING
- The `.env` file must be in the project root, not in `voice_pipeline/`
- Restart the shell if the variables were exported rather than written to `.env`

### Import errors
- Make sure the virtual environment is activated
- Run `pip install -r requirements.txt` again
- Run from the project root so `ML.voice_pipeline` resolves

### ASR rejects the audio format
The mobile client records `.m4a` (AAC). If the service accepts only WAV or FLAC, convert before sending:

```bash
ffmpeg -i voice-note.m4a -ar 16000 -ac 1 voice-note.wav
```

The format is detected from the file extension and declared in the request. If the service rejects the `audioFormat` field itself, set `declare_audio_format=False` in `config.py`.

### Transcription returns empty text
- Confirm the recording actually contains speech — a muted mic produces a valid but silent file
- Check the language code matches what the artisan actually spoke
- Recordings under about two seconds often return nothing

### Craft terms come back misspelled
- Pass `--category` so the relevant glossary terms are prioritised
- Add the missing term to the appropriate list in `glossary/craft_terms.py`
- Raise `glossary_terms_in_prompt` if the vocabulary is being truncated

### 401 or 403 from the endpoint
- The key is missing, expired, or belongs to a different host than `whisper_base_url`
- Run `python run_pipeline.py status` to confirm the key was picked up

### 429 rate limited
- The endpoint's request or audio quota for the period is exhausted
- Limits usually apply per organisation, so additional keys do not raise them

### Accuracy is poor on a regional language
- Whisper's training data is weighted toward English, so smaller Indian languages transcribe less accurately than Hindi
- Pass `--category` so craft vocabulary is prioritised in the prompt
- For a substantial improvement, swap in a model fine-tuned on Indian speech — the backend is chosen by `stt_provider`, so this is a registry entry rather than a rewrite

---

## Future Integration

This module is designed to be called from the FastAPI backend, which then hands the transcript to the catalog service:

```python
# Example future integration (NOT implemented here)
from ML.voice_pipeline import process_voice_note

@app.post("/api/v1/uploads/voice")
async def upload_voice(file: UploadFile, language_code: str = "hi"):
    audio_path = save_upload(file)
    voice = process_voice_note(audio_path, language_code=language_code)

    listing = await catalog_service.generate_listing(
        ListingGenerateRequest(
            transcript=voice["text_for_listing"],
            language_code=language_code,
        )
    )
    return {"status": "completed", "result": listing}
```

The `process_voice_note()` function is the single entry point — no changes needed to the pipeline logic.

---

## Limitations

- Transcription quality varies by language. Whisper's training data is weighted toward English, so Hindi transcribes well while the smaller Indian languages are noticeably weaker. Models fine-tuned on Indian speech close much of that gap and can be swapped in through the backend registry.
- Regional dialects filed under a single language code (Marwari, Bhojpuri, and Awadhi all sent as `hi`) transcribe less accurately than the standard form the models were trained on.
- Recording conditions are rarely clean. Workshop noise — a potter's wheel, a loom, hammering — measurably reduces accuracy, and the pipeline has no noise-reduction stage.
- Every stage requires connectivity. The Flutter app queues recordings offline and drains the queue when signal returns, so the artisan is never blocked, but nothing in this module runs without a network.
- The module processes one voice note at a time. Batch processing loops rather than running in parallel.
- Listing generation and text-to-speech are outside this module. Transcript quality is what it controls; how that transcript becomes a listing is the catalog service's concern.
- Artisans who cannot read cannot verify the transcript. The on-device read-back is what makes the result checkable, and it lives in the Flutter app, not here.

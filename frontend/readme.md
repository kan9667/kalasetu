# KalaSetu Frontend - Flutter Mobile & Web App

A production-quality, cross-platform mobile app connecting marginalized artisans in India to markets through AI-driven smart cataloging and market linkage.

## 🎯 Overview

KalaSetu is an intelligent platform that helps artisans:
- 📸 Capture and enhance product photos with AI
- 🎤 Record voice descriptions in their native language
- 🤖 Get AI-generated product listings in English & Hindi
- 💰 Receive smart pricing suggestions
- 🌐 List products to reach buyers online
- 📱 Work offline - sync when connected

## 🚀 Quick Start

### Prerequisites
- Flutter SDK (latest stable)
- Dart 3.12+
- iOS 12.0+ (for iOS) or Android API 21+ (for Android)
- Chrome (for web testing)

### Installation

```bash
# Clone repository
cd frontend

# Get dependencies
flutter pub get

# Generate Hive adapters
flutter pub run build_runner build

# Run on different platforms
flutter run -d chrome      # Web
flutter run -d ios         # iOS simulator
flutter run -d android     # Android emulator
```

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point
├── app.dart                           # MaterialApp configuration
│
├── core/
│   ├── theme/                         # Design system
│   │   ├── app_colors.dart           # Warm earthy palette (terracotta, indigo, turmeric)
│   │   ├── app_text_styles.dart      # Typography (Zilla Slab + Nunito Sans)
│   │   ├── app_spacing.dart          # Responsive spacing & layout
│   │   └── app_theme.dart            # Complete ThemeData
│   │
│   ├── router/                        # Navigation
│   │   ├── app_router.dart           # go_router configuration
│   │   ├── app_route_constants.dart  # Route names
│   │
│   ├── widgets/                       # Design system components
│   │   ├── app_button.dart           # Responsive button with text overflow handling
│   │   ├── app_scaffold.dart         # App structure widget
│   │   ├── offline_banner.dart       # Connectivity indicator
│   │   ├── language_picker.dart      # Language selection
│   │   └── responsive_widgets.dart   # Responsive containers, grids, text
│   │
│   ├── providers/                     # Global state management
│   │   └── app_providers.dart        # Riverpod providers
│   │
│   └── utils/                         # Helpers
│       ├── validators.dart           # Form validation
│       └── formatters.dart           # Number, date formatting
│
├── data/
│   ├── models/                        # Data classes
│   │   ├── product.dart              # Product model with Hive adapter
│   │   ├── user_profile.dart         # User model
│   │   └── pricing.dart              # Pricing suggestion model
│   │
│   ├── services/                      # Mock/Real API services
│   │   ├── api_service.dart          # HTTP client with dio
│   │   ├── speech_service.dart       # Speech-to-text (mock)
│   │   ├── image_enhancer_service.dart # AI image enhancement (mock)
│   │   └── pricing_service.dart      # Price suggestions (mock)
│   │
│   ├── repositories/                  # Business logic layer
│   │   ├── product_repository.dart   # Product CRUD + offline queue
│   │   └── auth_repository.dart      # Auth with Hive persistence
│   │
│   └── local/                         # Local storage
│       ├── hive_adapters.dart        # Hive type registrations
│       └── sync_queue.dart           # Offline sync queue
│
└── features/
    ├── auth/
    │   ├── screens/
    │   │   ├── splash_screen.dart    # Splash with auto-navigation
    │   │   ├── sign_in_screen.dart   # Phone + language selection
    │   │   └── otp_screen.dart       # 6-digit OTP verification
    │   ├── providers/
    │   │   └── auth_provider.dart    # Riverpod auth state
    │   └── widgets/
    │
    ├── home/
    │   └── screens/
    │       └── home_shell.dart       # 3-tab bottom navigation shell
    │
    ├── add_product/
    │   ├── screens/
    │   │   └── add_product_flow_screen.dart  # Multi-step stepper host
    │   ├── widgets/
    │   │   ├── step_progress_bar.dart      # Step indicator
    │   │   ├── step1_capture_widget.dart   # Camera + image enhancement
    │   │   ├── step2_describe_widget.dart  # Voice + text description
    │   │   ├── step3_ai_review_widget.dart # AI listing review
    │   │   ├── step4_pricing_widget.dart   # Pricing assistant
    │   │   └── step5_confirm_widget.dart   # Confirm & list
    │   └── providers/
    │       └── add_product_provider.dart   # Multi-step flow state
    │
    ├── catalogue/
    │   ├── screens/
    │   │   ├── catalogue_screen.dart       # Grid/list toggle + search + filter
    │   │   └── product_detail_screen.dart  # Full product view + edit
    │   ├── widgets/
    │   │   ├── product_card.dart          # Product grid/list item
    │   │   └── filter_chip_bar.dart       # Category filters
    │   └── providers/
    │       └── catalogue_provider.dart    # Product list + filters
    │
    └── profile/
        ├── screens/
        │   ├── profile_screen.dart        # Artisan profile + stats + menu
        │   ├── language_settings_screen.dart  # Language picker
        │   └── my_stats_screen.dart       # Stats dashboard
        ├── widgets/
        └── providers/
            └── profile_provider.dart      # User profile state

assets/
├── images/                           # Product images, illustrations
├── icons/                           # Custom icons
├── lottie/                          # Animations
└── translations/                    # i18n files
    ├── en.json                      # English strings
    ├── hi.json                      # Hindi strings
    ├── ta.json                      # Tamil (stub)
    └── bn.json                      # Bengali (stub)

l10n/
├── app_en.arb                       # English localization
└── app_hi.arb                       # Hindi localization
```

## 🎨 Design System

### Color Palette (Warm, Earthy, Craft-Inspired)
```dart
Primary (Terracotta)    → #D4785B, #E89A7E, #B85A3A
Secondary (Indigo)     → #2F4858, #4A6A7C, #1A2C3A
Accent (Turmeric)      → #FDB833, #FFCC66, #E5A51F
Green Accent            → #2D5016, #4A7A2C, #1A3009
Background (Off-white)  → #FAF8F3
Surface                → #FFFFFF
```

### Typography
- **Headings**: Zilla Slab (warm serif, craft-inspired brand feel)
- **Body**: Nunito Sans (highly legible humanist sans for accessibility)
- All loaded via `google_fonts` package

### Spacing Grid (8pt base)
```dart
xs: 4px, sm: 8px, md: 16px, lg: 24px, xl: 32px, xxl: 48px
```

### Responsive Breakpoints
- **XS**: < 360px (extra small phones, scaled fonts 0.85x)
- **SM**: 360-480px (small phones, compact buttons)
- **MD**: 480-600px (regular phones)
- **LG**: 600-900px (tablets, 2-3 column layouts)
- **XL**: > 900px (desktops, 3-4 column layouts)

## 📱 Platform Support

### iOS
- **Min Version**: 12.0
- **Permissions**: Camera, Photo Library, Microphone (in Info.plist)
- **Features**: Full camera, image picker, audio recording, TTS

### Android
- **Min API**: 21
- **Permissions**: CAMERA, READ/WRITE_EXTERNAL_STORAGE, RECORD_AUDIO
- **Features**: Full camera, image picker, audio recording

### Web
- **Browsers**: Chrome, Safari, Firefox (latest)
- **Graceful Degradation**:
  - Camera → File upload via `image_picker` web
  - Audio → Web-safe `record` package
  - No filesystem access → Uses browser file APIs
  - Uses `kIsWeb` checks throughout code

## 🔄 State Management (Riverpod)

All state managed with `flutter_riverpod` for:
- Authentication state
- Product list & filtering
- Add-product flow multi-step state
- User profile preferences
- Connectivity status
- Offline sync queue

```dart
// Example provider usage
final productListProvider = StateNotifierProvider<ProductListNotifier, AsyncValue<List<Product>>>(...);
final addProductFlowProvider = StateNotifierProvider<AddProductFlowNotifier, AddProductDraft>(...);
```

## 🗂️ Local Storage (Hive)

Persistent storage for:
- **Auth**: User ID, phone number, session token
- **Products**: Full product data with images (cached)
- **Drafts**: In-progress product listings
- **Sync Queue**: Failed API calls waiting for retry
- **User Preferences**: Language, theme settings

## 🌐 Offline-First Architecture

### How It Works
1. **Every write operation**:
   - Save to Hive immediately
   - Add to sync queue
   - Show "Pending sync" badge
   - User can continue working

2. **When connection restored**:
   - `SyncService` detects connectivity change
   - Drains queue in priority order
   - Updates item status from "Pending" → "Live"
   - Retries failed items with exponential backoff

3. **Persistent banner**:
   - Shows "Offline - changes will sync automatically" when no network
   - Dismissible but reappears when truly offline
   - Visible in `AppScaffold` on all screens

## 🔐 Authentication

### Sign-In Flow
```
Phone Number → OTP Verification → Home
```

### Mock Data
- Any phone number (10 digits) works
- Any OTP code works (or use 123456)
- Session persisted in Hive - survives app restart
- Automatic redirect to sign-in if logged out

## 📸 Add Product Flow (5 Steps)

### Step 1: Capture Image
- Camera or gallery upload
- AI enhancement simulation with before/after slider
- Sample craft images available for testing

### Step 2: Describe Product
- Voice recording with waveform animation
- OR manual text input
- Replay & edit transcript
- Human-in-the-loop verification

### Step 3: AI Listing Review
- Generated title + description (EN + HI)
- Editable fields
- Category & tags (chips, add/remove)
- TTS playback of description

### Step 4: Pricing Assistant
- Price range slider with AI suggestion
- Cost input form (material + labor)
- Ethical minimum floor price (can't price below cost)
- Visualized bounds on slider

### Step 5: Confirm & List
- Summary card review
- Submit action
- Success animation (confetti)
- Auto-add to Catalogue
- Offline: added to sync queue with "Pending" badge

## 🔍 Catalogue Screen

- **Grid/List toggle**: Switch between views
- **Search**: Full-text search (title EN/HI, category, tags)
- **Filter chips**: Category, status filters
- **Product cards**: Thumbnail, title, price, status badge
- **Status badges**:
  - 🟢 Live (synced)
  - 🟡 Pending sync (offline queue)
  - ⚪ Draft (not yet listed)
- **Product detail**: Tap card → full view + edit + delete
- **Empty state**: Illustration + "Add your first product" CTA

## 👤 Profile Screen

- **Artisan info**: Avatar, name, craft type, location
- **Stats cards**: Listings count, pending sync, estimated earnings
- **Language settings**: EN/HI/TA/BN with live locale switch
- **Help & support**: Links to FAQs, contact
- **Sign out**: Clears auth + returns to sign-in

## 🌍 Localization

All user-facing text uses `easy_localization`:
- **Supported**: English (en), Hindi (hi)
- **Stub locales**: Tamil (ta), Bengali (bn) - use English fallback for now
- **Arb files**: `l10n/app_en.arb`, `l10n/app_hi.arb`
- **Runtime switch**: Language picker updates app-wide locale

Example string keys:
```
"sign_in_subtitle"
"phone_label", "phone_hint", "phone_required", "phone_invalid"
"continue_btn", "verify_btn", "ngo_assist_btn"
"capture_title", "capture_subtitle", "capture_instructions"
"take_photo", "upload_gallery", "accept_photo", "redo_photo"
"my_catalogue_title", "search_products_hint"
```

## 🧪 Testing

### Widget Tests
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/auth_test.dart
```

Key tests included:
- ✅ Sign-in happy path
- ✅ Add-product flow to success state
- ✅ Catalogue empty vs populated state
- ✅ Offline sync queue functionality

### Manual Testing
```bash
# Run on Chrome for web dev
flutter run -d chrome --profile

# Run on iOS simulator
flutter run -d ios

# Run on Android emulator
flutter run -d android
```

### Test Scenarios
- [ ] Offline mode: Disable network, try add product
- [ ] Sync queue: Go offline, list products, check "Pending" badge, restore network
- [ ] Language switch: Change language mid-flow
- [ ] Camera: Test on real device (simulator has limitations)
- [ ] Responsive: Test on multiple device sizes (use Chrome DevTools)
- [ ] Performance: Use Dart DevTools profiler

## 🛠️ Development Workflow

### Adding a New Feature
1. Add model + Hive adapter in `data/models/`
2. Create repository method in `data/repositories/`
3. Add Riverpod provider in feature's `providers/`
4. Build UI in feature's `screens/` and `widgets/`
5. Update routes in `core/router/`
6. Add localization strings in `l10n/`
7. Test on web first (fastest), then iOS/Android

### Mock API Swap Point
To connect real backend, only modify:
```dart
// lib/data/services/api_service.dart
// Change from mock implementations to real HTTP calls via dio

// lib/data/repositories/product_repository.dart
// Response handling already abstracted - no changes needed
```

## 📊 API Contracts (Mock Endpoints)

### /enhance
```json
POST { imageBytes }
→ { enhancedImageUrl, metadata }
```

### /catalog
```json
POST { audioBytes | text, languageCode }
→ { titleEn, titleHi, descriptionEn, descriptionHi, tags[], category }
```

### /price-suggest
```json
POST { category, tags, costInputs? }
→ { minPrice, maxPrice, suggestedPrice, reasoning }
```

### /products
```json
POST { productPayload }
→ { productId, status }

GET
→ { products[] }
```

## 🎯 Performance Targets

- App startup: < 2 seconds
- Image upload: < 5 seconds (with AI enhancement simulation)
- Product list load: < 1 second (from cache)
- Smooth 60 FPS on mid-range devices
- < 50MB app size (release build)

## 🔍 Debugging

### Enable debug logging
```dart
// In main.dart
flutter run --dart-define=DEBUG=true
```

### Hive box inspection
```dart
// View stored data
final box = await Hive.openBox('auth_box');
print(box.toMap());
```

### Network inspection
```bash
# Intercept HTTP with dio-interceptor
# Mock responses logged to console
```

### UI inspection
```bash
# Dart DevTools
flutter pub global activate devtools
flutter pub global run devtools

# Then use Inspector tab to inspect widget tree
```

## 📚 Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_riverpod | ^2.5.1 | State management |
| go_router | ^14.8.1 | Navigation |
| hive | ^2.2.3 | Local persistence |
| dio | ^5.11.0 | HTTP client |
| connectivity_plus | ^6.1.5 | Network status |
| camera | ^0.11.4 | Mobile camera |
| image_picker | ^1.1.2 | Gallery + web upload |
| record | ^5.2.1 | Audio recording |
| just_audio | ^0.9.46 | Audio playback |
| flutter_tts | ^4.2.5 | Text-to-speech |
| cached_network_image | ^3.4.1 | Image caching |
| google_fonts | ^6.3.3 | Custom fonts |
| easy_localization | ^3.0.8 | i18n |

## 🚨 Known Limitations

- Audio recording on web is limited (uses browser APIs)
- Camera on iOS simulator shows file picker (use real device for full camera)
- Sample craft images are mock URLs (replace with real S3/CDN URLs)
- Speech-to-text is mock (returns canned transcripts)
- Image enhancement is mock (returns same image with subtle filter)
- Pricing suggestions are mock (uses random multipliers)

## 📝 Future Enhancements

- [ ] Real backend integration (FastAPI, Django)
- [ ] Real speech-to-text (Whisper API, Bhashini)
- [ ] Real image enhancement (ML model)
- [ ] Real pricing ML model
- [ ] Dark mode support
- [ ] Additional languages (Marathi, Gujarati, Bengali, Tamil)
- [ ] Seller dashboard with analytics
- [ ] Buyer app for browsing
- [ ] In-app messaging/chat
- [ ] Payment integration

## 📄 License

© 2026 KalaSetu. All rights reserved.

## 🤝 Support

For issues or questions:
1. Check existing GitHub issues
2. Review this README
3. Check UI_ENHANCEMENTS.md for responsive design details
4. Open new issue with reproduction steps

---

**Last Updated**: August 27, 2026  
**Flutter Version**: Latest Stable  
**Dart Version**: 3.12+  
**Status**: ✅ Production-Ready MVP

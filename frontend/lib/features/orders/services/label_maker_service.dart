import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order.dart';

/// Service responsible for generating the printable "Artisan Story & Packaging Label"
/// with bilingual craft story, wash-care instructions, QR code, and order details.
class LabelMakerService {
  LabelMakerService._();

  // TODO: Stub URL until ONDC profile endpoint is live; swap in production URL here.
  static const String _ondcProfileBaseUrl = 'https://kalasetu.ondc.org/artisan';

  /// Default bilingual craft stories per category.
  static (String en, String hi) defaultCraftStoryFor(String category) {
    switch (category.toLowerCase()) {
      case 'pottery':
        return (
          'Handcrafted using traditional terracotta clay techniques passed down through generations. Shaped by hand on the potter\'s wheel and wood-fired for authentic earthy warmth.',
          'पीढ़ियों से चली आ रही पारंपरिक मिट्टी कला द्वारा हस्तनिर्मित। चाक पर हाथ से गढ़ा गया और प्राकृतिक लकड़ी की आंच में पकाया गया।',
        );
      case 'textiles':
        return (
          'Hand-woven on heritage wooden pit looms by master artisans. Crafted using pure natural fibers and time-honored weave motifs reflecting centuries of regional identity.',
          'कुशल बुनकरों द्वारा पारंपरिक हथकरघे पर बुना गया। प्राकृतिक रेशों और विरासत बुनाई से तैयार एक अनूठी कृति।',
        );
      case 'jewelry':
        return (
          'Intricately handcrafted using heritage metalwork, filigree, and enameling traditions. Each unique piece embodies meticulous patience and artisanal pride.',
          'पारंपरिक धातु कला और मीनाकारी से बारीकी से तैयार। प्रत्येक आभूषण कारीगर के हुनर और समर्पण का प्रतीक है।',
        );
      case 'metalwork':
        return (
          'Cast using ancient lost-wax and hand-hammered metallurgy traditions. Sturdy, timeless, and deeply rooted in Indian cultural legacy.',
          'प्राचीन ढलाई और हाथ की नक्काशी तकनीक से निर्मित। टिकाऊ, अद्वितीय और सांस्कृतिक विरासत से परिपूर्ण।',
        );
      case 'woodwork':
        return (
          'Carved from sustainably sourced seasoned timber by skilled wood craftsmen. Finished with non-toxic, eco-friendly natural plant-based polishes.',
          'कुशल काष्ठ शिल्पियों द्वारा स्थानीय लकड़ी से तराशा गया। प्राकृतिक और पर्यावरण-अनुकूल पॉलिश से सुरक्षित।',
        );
      case 'paintings':
        return (
          'Hand-painted using indigenous folk traditions and natural organic pigments. Each canvas tells stories of folklore, nature, and community heritage.',
          'पारंपरिक लोक कला शैली में प्राकृतिक रंगों से हाथ से चित्रित। प्राचीन लोककथाओं और प्रकृति का सुंदर संगम।',
        );
      default:
        return (
          'Authentic handcrafted creation made with pride, sustainable materials, and traditional techniques under the KalaSetu artisan initiative.',
          'कलासेतु पहल के तहत स्थानीय कारीगरों द्वारा पारंपरिक कौशल, प्राकृतिक सामग्री और गौरव के साथ निर्मित प्रामाणिक हस्तशिल्प।',
        );
    }
  }

  /// Default bilingual wash-care and handling instructions per category.
  static (String en, String hi) defaultWashCareFor(String category) {
    switch (category.toLowerCase()) {
      case 'pottery':
        return (
          'Handle with care. Gentle hand wash with mild soap. Avoid direct thermal shock or open flames unless stated.',
          'सावधानी से रखें। हल्के साबुन से हाथ से धोएं। जब तक कहा न जाए, सीधी आंच से बचाएं।',
        );
      case 'textiles':
        return (
          'Hand wash cold separately with mild detergent. Dry flat in shade. Iron on reverse side on low heat.',
          'ठंडे पानी में अलग से हाथ से धोएं। छाया में सुखाएं। हल्के डिटर्जेंट का उपयोग करें।',
        );
      case 'jewelry':
        return (
          'Store in a soft dry pouch. Keep away from water, perfumes, moisture, and harsh chemicals.',
          'सूखे मुलायम पाउच में रखें। परफ्यूम, पानी और रसायनों के सीधे संपर्क से बचाएं।',
        );
      case 'metalwork':
        return (
          'Wipe with a clean dry cotton cloth. Avoid abrasive scrubs and prolonged moisture to maintain natural patina.',
          'मुलायम सूखे कपड़े से पोंछें। चमक बनाए रखने के लिए अत्यधिक नमी से बचाएं।',
        );
      case 'woodwork':
        return (
          'Keep away from direct prolonged sunlight and standing water. Clean with a soft dry or slightly damp cloth.',
          'तेज धूप और पानी से दूर रखें। सूखे अथवा हल्के नम मुलायम कपड़े से साफ करें।',
        );
      case 'paintings':
        return (
          'Keep framed under glass in a moisture-free area. Avoid direct exposure to harsh continuous sunlight.',
          'कांच के फ्रेम में सूखी जगह पर रखें। सीधी धूप और नमी से बचाकर रखें।',
        );
      default:
        return (
          'Handle with love and care. Keep in a dry, clean place away from extreme temperatures.',
          'स्नेह और सावधानी से रखें। अत्यधिक नमी और धूप से बचाकर सुरक्षित स्थान पर रखें।',
        );
    }
  }

  /// Returns the cache file path for an order's label.
  static Future<File> _getCacheFile(String orderId, OrderStatus status) async {
    final dir = await getApplicationDocumentsDirectory();
    final labelsDir = Directory('${dir.path}/packaging_labels');
    if (!await labelsDir.exists()) {
      await labelsDir.create(recursive: true);
    }
    return File('${labelsDir.path}/label_${orderId}_${status.name}.pdf');
  }

  /// Invalidates (deletes) cached label PDF for the given order.
  static Future<void> invalidateCache(String orderId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final labelsDir = Directory('${dir.path}/packaging_labels');
      if (await labelsDir.exists()) {
        final files = labelsDir.listSync();
        for (final entity in files) {
          if (entity is File && entity.path.contains('label_$orderId')) {
            await entity.delete();
            debugPrint('[LabelMaker] Invalidated cache: ${entity.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('[LabelMaker] Error invalidating cache: $e');
    }
  }

  /// Checks if a valid cached label exists for this order.
  static Future<File?> getCachedLabel(String orderId, OrderStatus status) async {
    try {
      final file = await _getCacheFile(orderId, status);
      if (await file.exists()) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Generates (or pulls from cache) a printable label PDF for [order]
  /// and shows the platform print/share sheet.
  static Future<bool> generateAndShare({
    required BuildContext context,
    required Order order,
    required String artisanName,
    String? artisanId,
    String? artisanCluster,
    String? craftType,
    String? customStoryEn,
    String? customStoryHi,
    bool forceRegenerate = false,
  }) async {
    try {
      final cacheFile = await _getCacheFile(order.id, order.status);
      final isCustomStory = customStoryEn != null || customStoryHi != null;

      Uint8List bytes;
      if (!forceRegenerate && !isCustomStory && await cacheFile.exists()) {
        debugPrint('[LabelMaker] Serving label from cache: ${cacheFile.path}');
        bytes = await cacheFile.readAsBytes();
      } else {
        debugPrint('[LabelMaker] Generating fresh label for order: ${order.id}');
        if (isCustomStory) {
          // Cache is invalidated whenever the story text is edited
          await invalidateCache(order.id);
        }
        final pdf = await _buildSinglePdf(
          order: order,
          artisanName: artisanName,
          artisanId: artisanId,
          artisanCluster: (artisanCluster != null && artisanCluster.isNotEmpty)
              ? artisanCluster
              : 'Kumhar Gram, Delhi NCR',
          craftType: craftType ?? order.productCategory,
          storyEn: customStoryEn,
          storyHi: customStoryHi,
        );
        bytes = await pdf.save();
        // Save to cache
        await cacheFile.writeAsBytes(bytes);
      }

      await Printing.sharePdf(
        bytes: bytes,
        filename: 'packaging_label_${order.id}.pdf',
      );
      return true;
    } catch (e, st) {
      debugPrint('[LabelMaker] Error generating/sharing label: $e\n$st');
      return false;
    }
  }

  /// Batch generation for multiple orders in one print job.
  static Future<bool> generateAndShareBatch({
    required BuildContext context,
    required List<Order> orders,
    required String artisanName,
    String? artisanId,
    String? artisanCluster,
    String? craftType,
  }) async {
    if (orders.isEmpty) return false;

    try {
      final doc = pw.Document();

      // Load fonts
      final fonts = await _loadFonts();

      for (final order in orders) {
        final (defaultStoryEn, defaultStoryHi) = defaultCraftStoryFor(order.productCategory);
        final (defaultWashEn, defaultWashHi) = defaultWashCareFor(order.productCategory);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a5,
            margin: const pw.EdgeInsets.all(16),
            build: (ctx) => _buildLabelContent(
              order: order,
              artisanName: artisanName,
              artisanId: artisanId,
              artisanCluster: (artisanCluster != null && artisanCluster.isNotEmpty)
                  ? artisanCluster
                  : 'Kumhar Gram, Delhi NCR',
              craftType: craftType ?? order.productCategory,
              storyEn: defaultStoryEn,
              storyHi: defaultStoryHi,
              washEn: defaultWashEn,
              washHi: defaultWashHi,
              fonts: fonts,
            ),
          ),
        );
      }

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'packaging_labels_batch_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      return true;
    } catch (e, st) {
      debugPrint('[LabelMaker] Batch error: $e\n$st');
      return false;
    }
  }

  /// Helper to load Devangari and Latin fonts safely.
  static Future<_PdfFonts> _loadFonts() async {
    pw.Font regular = pw.Font.helvetica();
    pw.Font bold = pw.Font.helveticaBold();
    pw.Font hindiRegular = pw.Font.helvetica();
    pw.Font hindiBold = pw.Font.helveticaBold();

    try {
      regular = await PdfGoogleFonts.notoSansRegular();
      bold = await PdfGoogleFonts.notoSansBold();
    } catch (e) {
      debugPrint('[LabelMaker] Latin Google font fallback: $e');
    }

    try {
      hindiRegular = await PdfGoogleFonts.notoSansDevanagariRegular();
      hindiBold = await PdfGoogleFonts.notoSansDevanagariBold();
    } catch (e) {
      debugPrint('[LabelMaker] Hindi Google font fallback: $e');
      hindiRegular = regular;
      hindiBold = bold;
    }

    return _PdfFonts(
      regular: regular,
      bold: bold,
      hindiRegular: hindiRegular,
      hindiBold: hindiBold,
    );
  }

  static Future<pw.Document> _buildSinglePdf({
    required Order order,
    required String artisanName,
    String? artisanId,
    required String artisanCluster,
    required String craftType,
    String? storyEn,
    String? storyHi,
  }) async {
    final doc = pw.Document();
    final fonts = await _loadFonts();

    final (defaultStoryEn, defaultStoryHi) = defaultCraftStoryFor(order.productCategory);
    final (defaultWashEn, defaultWashHi) = defaultWashCareFor(order.productCategory);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) => _buildLabelContent(
          order: order,
          artisanName: artisanName,
          artisanId: artisanId,
          artisanCluster: artisanCluster,
          craftType: craftType,
          storyEn: storyEn ?? defaultStoryEn,
          storyHi: storyHi ?? defaultStoryHi,
          washEn: defaultWashEn,
          washHi: defaultWashHi,
          fonts: fonts,
        ),
      ),
    );

    return doc;
  }

  static pw.Widget _buildLabelContent({
    required Order order,
    required String artisanName,
    String? artisanId,
    required String artisanCluster,
    required String craftType,
    required String storyEn,
    required String storyHi,
    required String washEn,
    required String washHi,
    required _PdfFonts fonts,
  }) {
    final terracotta = PdfColor.fromHex('#C97B5A');
    final darkTerracotta = PdfColor.fromHex('#8C533E');
    final parchment = PdfColor.fromHex('#FAF7F2');
    final borderCol = PdfColor.fromHex('#E6DDD0');

    // Dynamic URL for ONDC artisan profile
    final effectiveId = (artisanId != null && artisanId.isNotEmpty) ? artisanId : 'artisan_01';
    final ondcUrl = '$_ondcProfileBaseUrl/$effectiveId';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: terracotta, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.white,
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 1. Header Bar
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: terracotta,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'KalaSetu',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 16,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'ARTISAN STORY & PACKAGING LABEL',
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 7,
                        letterSpacing: 0.8,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      order.id,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 11,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${order.placedAt.day}/${order.placedAt.month}/${order.placedAt.year}',
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 7,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 8),

          // 2. Artisan Section & Verification Bar
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: parchment,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: borderCol),
            ),
            child: pw.Row(
              children: [
                // Artisan Initial Avatar
                pw.Container(
                  width: 32,
                  height: 32,
                  decoration: pw.BoxDecoration(
                    color: terracotta,
                    shape: pw.BoxShape.circle,
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    artisanName.isNotEmpty ? artisanName[0].toUpperCase() : 'A',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      color: PdfColors.white,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        artisanName,
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: darkTerracotta,
                        ),
                      ),
                      pw.Text(
                        '$craftType  •  $artisanCluster',
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#E7F4E8'),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: PdfColor.fromHex('#A3D9A5'), width: 0.5),
                  ),
                  child: pw.Text(
                    'ONDC VERIFIED ARTISAN',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 6.5,
                      color: PdfColor.fromHex('#2E7D32'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 8),

          // 3. Bilingual Craft Story Block
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderCol),
              borderRadius: pw.BorderRadius.circular(6),
              color: PdfColors.white,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'THE ARTISAN\'S STORY',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7.5,
                        color: terracotta,
                        letterSpacing: 0.8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'हस्तशिल्प की कहानी',
                      style: pw.TextStyle(
                        font: fonts.hindiBold,
                        fontSize: 7.5,
                        color: terracotta,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  storyEn,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    lineSpacing: 1.2,
                    color: PdfColors.grey900,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  storyHi,
                  style: pw.TextStyle(
                    font: fonts.hindiRegular,
                    fontSize: 8,
                    lineSpacing: 1.2,
                    color: PdfColors.grey800,
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 8),

          // 4. Middle Section: Wash-Care & QR Code
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Wash-Care Block
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderCol),
                    borderRadius: pw.BorderRadius.circular(6),
                    color: parchment,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CARE & HANDLING  /  देखभाल निर्देश',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 7,
                          color: terracotta,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        washEn,
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 7.5,
                          lineSpacing: 1.1,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        washHi,
                        style: pw.TextStyle(
                          font: fonts.hindiRegular,
                          fontSize: 7.5,
                          lineSpacing: 1.1,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(width: 8),

              // QR Code Block
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderCol),
                    borderRadius: pw.BorderRadius.circular(6),
                    color: PdfColors.white,
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.SizedBox(
                        width: 52,
                        height: 52,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: ondcUrl,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Scan for ONDC Profile',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 6,
                          fontWeight: pw.FontWeight.bold,
                          color: terracotta,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        'Verify craft origin',
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 5.5,
                          color: PdfColors.grey600,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 8),

          // 5. Order & Delivery Details Table
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderCol),
              borderRadius: pw.BorderRadius.circular(6),
              color: PdfColors.white,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'PACKAGE & BUYER DETAILS',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7.5,
                        color: terracotta,
                        letterSpacing: 0.8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'DELIVER TO: ${order.buyerCity.toUpperCase()}',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7.5,
                        color: PdfColors.grey800,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            order.productTitle,
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Category: ${order.productCategory}  •  Qty: ${order.quantity}',
                            style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 7.5,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            '₹${order.amount.toStringAsFixed(0)}',
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: terracotta,
                            ),
                          ),
                          pw.Text(
                            '${order.buyerName}, ${order.buyerLocation}',
                            style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 7.5,
                              color: PdfColors.grey700,
                            ),
                            textAlign: pw.TextAlign.end,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (order.trackingId != null) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Tracking ID: ${order.trackingId}',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ],
            ),
          ),

          pw.Spacer(),

          // 6. Footer Tagline
          pw.Divider(color: borderCol, thickness: 0.8),
          pw.Center(
            child: pw.Text(
              'Crafted with pride. Packed with care. Delivered with love. — KalaSetu',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 7.5,
                color: PdfColors.grey700,
                fontStyle: pw.FontStyle.italic,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font hindiRegular;
  final pw.Font hindiBold;

  _PdfFonts({
    required this.regular,
    required this.bold,
    required this.hindiRegular,
    required this.hindiBold,
  });
}

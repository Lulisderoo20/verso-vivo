import 'dart:math';

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VersoVivoApp());
}

class VersoVivoApp extends StatelessWidget {
  const VersoVivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1B7F6D),
        secondary: Color(0xFFB28A39),
        surface: Color(0xFFFFF8EF),
        onPrimary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1E2525),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VersoVivo',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(baseTheme.textTheme),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const VerseHomePage(),
    );
  }
}

class VerseHomePage extends StatefulWidget {
  const VerseHomePage({super.key});

  @override
  State<VerseHomePage> createState() => _VerseHomePageState();
}

class _VerseHomePageState extends State<VerseHomePage> {
  static const String _appName = 'VersoVivo';
  static const String _question =
      '¿Sobre qué quieres que trate el versículo de hoy?';
  static const String _welcomeMessage =
      'Primera app de las chicas cristianas de GBA y CABA de la Provincia de Buenos Aires, Argentina.\n'
      'Que nuestro trabajo celebre a Dios cada día.\n'
      'Gracias a todas por poner su corazón en Jesús y compartirlo.\n'
      'Espero que que éste sea el camino a grandes logros en pos de Su voluntad.\n'
      '\n'
      'Las quiero mucho!! 💗.';
  static const String _webUrl = 'https://verso-vivo.pages.dev';
  static const String _androidUrl =
      'https://play.google.com/store/apps/details?id=com.usuario.verso_vivo';
  static const String _iosUrl = 'https://apps.apple.com/app/id0000000000';
  static const String _bibleApiBaseUrl =
      'https://raw.githubusercontent.com/maatheusgois/bible/main/versions/es/rvr';

  final TextEditingController _topicController = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final Random _random = Random();

  VerseCardData? _selectedVerse;
  String _voiceStatus = 'Escribe o usa el micrófono para contar tu tema.';
  String _lastTopic = '';
  String? _spanishLocaleId;
  String _lastTranscript = '';
  bool _isStoppingListening = false;
  bool _ttsReady = false;
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _showWelcomeOverlay = true;

  @override
  void initState() {
    super.initState();
    _configureVoiceTools();
  }

  Future<void> _configureVoiceTools() async {
    await _initializeSpeech();

    try {
      await _flutterTts.awaitSpeakCompletion(true);
      await _ensureSpanishTtsVoice();
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);
      _flutterTts.setStartHandler(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSpeaking = true;
        });
      });
      _flutterTts.setCompletionHandler(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSpeaking = false;
        });
      });
      _flutterTts.setErrorHandler((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSpeaking = false;
        });
      });
      _ttsReady = true;
    } catch (_) {
      // If TTS is unavailable on a target platform, text mode still works.
      _ttsReady = false;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (_speechEnabled) {
        _voiceStatus =
            'Micrófono listo. Habla o escribe y luego toca buscar.';
      } else {
        _voiceStatus =
            'Micrófono no disponible aquí. Verifica permiso de micrófono en Chrome.';
      }
    });
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == 'done' || status == 'notListening') {
      if (_isStoppingListening) {
        _isStoppingListening = false;
        return;
      }
      setState(() {
        _isListening = false;
        _voiceStatus = 'Transcripción lista. Toca buscar versículo.';
      });
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _voiceStatus =
          'No entendí el audio con claridad. Puedes intentar otra vez.';
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechEnabled) {
      await _initializeSpeech();
    }

    if (!_speechEnabled) {
      _showSnackBar(
        'El reconocimiento de voz no está disponible. Habilita el micrófono en Chrome.',
      );
      return;
    }

    if (_isListening || _speechToText.isListening) {
      await _stopListening(discardResult: true);
      return;
    }

    final localeId = _spanishLocaleId ?? 'es-ES';

    await _speechToText.listen(
      onResult: _onSpeechResult,
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: true,
      ),
      listenFor: const Duration(seconds: 25),
      pauseFor: const Duration(seconds: 4),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = true;
      _voiceStatus = 'Te escucho ahora...';
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) {
      return;
    }

    _lastTranscript = result.recognizedWords;
    setState(() {
      _topicController.text = result.recognizedWords;
      _topicController.selection = TextSelection.fromPosition(
        TextPosition(offset: _topicController.text.length),
      );
      _voiceStatus = result.finalResult
          ? 'Transcripción lista. Toca buscar versículo.'
          : 'Escuchando...';
    });
  }

  Future<void> _buildVerseForTopic() async {
    if (_isListening || _speechToText.isListening) {
      await _stopListening(discardResult: false);
    }

    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showSnackBar('Primero escribe o dicta el tema del versículo.');
      return;
    }

    final parsedReference = _parseBibleReference(topic);
    VerseCardData? verseFromReference;
    if (parsedReference != null) {
      if (mounted) {
        setState(() {
          _voiceStatus = 'Buscando referencia bíblica...';
        });
      }
      verseFromReference = await _fetchVerseFromBibleApi(parsedReference);
      if (verseFromReference == null) {
        _showSnackBar(
          'No encontré esa referencia exacta. Te muestro un versículo relacionado.',
        );
      }
    }

    final verse = verseFromReference ?? _pickVerse(topic);
    setState(() {
      _selectedVerse = verse;
      _lastTopic = topic;
      _voiceStatus = 'Versículo listo. Puedes leerlo o compartirlo.';
    });

    await _speak(
      'Sobre $topic, este es tu versículo de hoy. ${verse.text}. ${verse.reference}.',
    );
  }

  VerseCardData _pickVerse(String topic) {
    final verseByReference = _pickVerseByReference(topic);
    if (verseByReference != null) {
      return verseByReference;
    }

    final normalizedTopic = _normalize(topic);
    final scoredMatches = <MapEntry<VerseCardData, int>>[];

    for (final verse in _verseCatalog) {
      var score = 0;
      for (final keyword in verse.keywords) {
        if (normalizedTopic.contains(_normalize(keyword))) {
          score++;
        }
      }
      if (score > 0) {
        scoredMatches.add(MapEntry(verse, score));
      }
    }

    if (scoredMatches.isNotEmpty) {
      scoredMatches.sort((a, b) => b.value.compareTo(a.value));
      final topScore = scoredMatches.first.value;
      final topVerses = scoredMatches
          .where((entry) => entry.value == topScore)
          .map((entry) => entry.key)
          .toList();
      return topVerses[_random.nextInt(topVerses.length)];
    }

    return _verseCatalog[_random.nextInt(_verseCatalog.length)];
  }

  _BibleParsedReference? _parseBibleReference(String input) {
    var normalized = _normalizeReferenceInput(input);
    if (normalized.isEmpty) {
      return null;
    }

    normalized = normalized
        .replaceAll(
          RegExp(r'\b(primera|primer|1ra|1er|i)\b'),
          '1',
        )
        .replaceAll(
          RegExp(r'\b(segunda|segundo|2da|2do|ii)\b'),
          '2',
        )
        .replaceAll(
          RegExp(r'\b(tercera|tercer|3ra|3er|iii)\b'),
          '3',
        );
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    _BibleBookDefinition? matchedBook;
    String matchedAlias = '';

    for (final book in _bibleBooks) {
      for (final alias in book.aliases) {
        final pattern = RegExp(
          r'(^|\s)' + RegExp.escape(alias) + r'(?=\s|$)',
        );
        if (pattern.hasMatch(normalized) && alias.length > matchedAlias.length) {
          matchedBook = book;
          matchedAlias = alias;
        }
      }
    }

    if (matchedBook == null) {
      return null;
    }

    final numbersSource = normalized
        .replaceFirst(
          RegExp(r'(^|\s)' + RegExp.escape(matchedAlias) + r'(?=\s|$)'),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(de|del|la|el|los|las|libro|carta|epistola|evangelio|segun|san|santo)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    int? chapter;
    int? verseStart;
    int? verseEnd;

    final chapterVerseMatch = RegExp(
      r'(\d{1,3})\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?',
    ).firstMatch(numbersSource);
    if (chapterVerseMatch != null) {
      chapter = int.tryParse(chapterVerseMatch.group(1)!);
      verseStart = int.tryParse(chapterVerseMatch.group(2)!);
      verseEnd = int.tryParse(chapterVerseMatch.group(3) ?? '');
    } else {
      final matches = RegExp(
        r'\d{1,3}',
      ).allMatches(numbersSource).map((m) => int.parse(m.group(0)!)).toList();
      if (matches.isNotEmpty) {
        chapter = matches[0];
      }
      if (matches.length >= 2) {
        verseStart = matches[1];
      }
      if (matches.length >= 3) {
        verseEnd = matches[2];
      }
    }

    chapter ??= 1;
    if (chapter < 1) {
      return null;
    }

    if (verseStart != null && verseStart < 1) {
      verseStart = 1;
    }
    if (verseEnd != null && verseEnd < 1) {
      verseEnd = verseStart;
    }

    return _BibleParsedReference(
      bookId: matchedBook.id,
      bookName: matchedBook.name,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
    );
  }

  Future<VerseCardData?> _fetchVerseFromBibleApi(
    _BibleParsedReference reference,
  ) async {
    final chapter = reference.chapter ?? 1;
    final verses = <String>[];
    var startVerse = reference.verseStart;
    var endVerse = reference.verseEnd;

    if (startVerse != null) {
      endVerse ??= startVerse;
      if (endVerse < startVerse) {
        endVerse = startVerse;
      }
      const maxRange = 8;
      if (endVerse - startVerse + 1 > maxRange) {
        endVerse = startVerse + maxRange - 1;
      }

      var lastFetchedVerse = startVerse;
      for (var verse = startVerse; verse <= endVerse; verse++) {
        final text = await _fetchBibleVerseText(reference.bookId, chapter, verse);
        if (text == null) {
          if (verse == startVerse) {
            return null;
          }
          break;
        }
        verses.add(text);
        lastFetchedVerse = verse;
      }

      if (verses.isEmpty) {
        return null;
      }

      final verseSuffix = lastFetchedVerse == startVerse
          ? '$chapter:$startVerse'
          : '$chapter:$startVerse-$lastFetchedVerse';

      return VerseCardData(
        reference: '${reference.bookName} $verseSuffix',
        text: verses.join(' '),
        keywords: [reference.bookName.toLowerCase()],
      );
    }

    const previewVerses = 5;
    var lastFetchedVerse = 0;
    for (var verse = 1; verse <= previewVerses; verse++) {
      final text = await _fetchBibleVerseText(reference.bookId, chapter, verse);
      if (text == null) {
        break;
      }
      verses.add('$verse. $text');
      lastFetchedVerse = verse;
    }

    if (verses.isEmpty) {
      return null;
    }

    return VerseCardData(
      reference: '${reference.bookName} $chapter:1-$lastFetchedVerse',
      text: verses.join(' '),
      keywords: [reference.bookName.toLowerCase()],
    );
  }

  Future<String?> _fetchBibleVerseText(String bookId, int chapter, int verse) async {
    final uri = Uri.parse('$_bibleApiBaseUrl/$bookId/$chapter/$verse.json');
    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is String) {
        final clean = decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
        return clean.isEmpty ? null : clean;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _normalizeReferenceInput(String value) {
    const source = 'áéíóúüñ';
    const target = 'aeiouun';

    var output = value.toLowerCase();
    for (var i = 0; i < source.length; i++) {
      output = output.replaceAll(source[i], target[i]);
    }

    output = output.replaceAll(RegExp(r'[^a-z0-9:\-\s]'), ' ');
    return output.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  VerseCardData? _pickVerseByReference(String topic) {
    final normalizedTopic = _normalize(topic);

    final salmoMatch = RegExp(r'\bsalmo?s?\s+(\d{1,3})\b').firstMatch(
      normalizedTopic,
    );
    if (salmoMatch != null) {
      final chapter = int.tryParse(salmoMatch.group(1)!);
      if (chapter != null) {
        return _findVerseByBookAndChapter(
          bookQuery: 'salmo',
          chapter: chapter,
        );
      }
    }

    final corintiosMatch = RegExp(
      r'\b(?:([12])\s+)?corint(?:ios|os)\s+(\d{1,3})\b',
    ).firstMatch(normalizedTopic);
    if (corintiosMatch != null) {
      final prefix = corintiosMatch.group(1);
      final chapter = int.tryParse(corintiosMatch.group(2)!);
      if (chapter == null) {
        return null;
      }
      if (prefix != null) {
        return _findVerseByBookAndChapter(
          bookQuery: '$prefix corintios',
          chapter: chapter,
        );
      }
      return _findVerseByBookAndChapter(bookQuery: '1 corintios', chapter: chapter) ??
          _findVerseByBookAndChapter(bookQuery: '2 corintios', chapter: chapter) ??
          _findVerseByBookAndChapter(bookQuery: 'corintios', chapter: chapter);
    }

    final genericReferenceMatch = RegExp(r'^([a-z]+)\s+(\d{1,3})\b').firstMatch(
      normalizedTopic,
    );
    if (genericReferenceMatch != null) {
      final chapter = int.tryParse(genericReferenceMatch.group(2)!);
      if (chapter != null) {
        return _findVerseByBookAndChapter(
          bookQuery: genericReferenceMatch.group(1)!,
          chapter: chapter,
        );
      }
    }

    return null;
  }

  VerseCardData? _findVerseByBookAndChapter({
    required String bookQuery,
    required int chapter,
  }) {
    final normalizedBookQuery = _normalize(bookQuery);
    final matches = <VerseCardData>[];

    for (final verse in _verseCatalog) {
      final parsed = _extractBookAndChapter(verse.reference);
      if (parsed == null || parsed.chapter != chapter) {
        continue;
      }

      if (_matchesBookQuery(
        queryBook: normalizedBookQuery,
        referenceBook: parsed.book,
      )) {
        matches.add(verse);
      }
    }

    if (matches.isEmpty) {
      return null;
    }
    return matches[_random.nextInt(matches.length)];
  }

  ({String book, int chapter})? _extractBookAndChapter(String reference) {
    final normalizedReference = _normalize(reference);
    final match = RegExp(
      r'^((?:1|2)\s+)?([a-z]+)\s+(\d{1,3})\b',
    ).firstMatch(normalizedReference);
    if (match == null) {
      return null;
    }

    final chapter = int.tryParse(match.group(3)!);
    if (chapter == null) {
      return null;
    }

    final prefix = match.group(1)?.trim();
    final baseBook = match.group(2)!;
    final book = prefix == null ? baseBook : '$prefix $baseBook';
    return (book: book, chapter: chapter);
  }

  bool _matchesBookQuery({
    required String queryBook,
    required String referenceBook,
  }) {
    if (queryBook == referenceBook) {
      return true;
    }

    if (queryBook == 'salmos') {
      return referenceBook == 'salmo';
    }

    if (queryBook == 'corintios' || queryBook == 'corintos') {
      return referenceBook.contains('corintios') ||
          referenceBook.contains('corintos');
    }

    return referenceBook.endsWith(' $queryBook');
  }

  String _normalize(String value) {
    const source = 'áéíóúüñ';
    const target = 'aeiouun';

    var output = value.toLowerCase();
    for (var i = 0; i < source.length; i++) {
      output = output.replaceAll(source[i], target[i]);
    }

    output = output.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return output.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _speakSelectedVerse() async {
    final verse = _selectedVerse;
    if (verse == null) {
      _showSnackBar('Aún no hay versículo para leer.');
      return;
    }
    await _speak('${verse.text}. ${verse.reference}.');
  }

  Future<void> _speak(String text) async {
    try {
      if (!_ttsReady) {
        await _configureVoiceTools();
      }
      final hasSpanishVoice = await _ensureSpanishTtsVoice();
      if (!hasSpanishVoice) {
        _showSnackBar(
          'No hay voz en español disponible en este navegador.',
        );
        return;
      }
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (_) {
      _showSnackBar('No pude reproducir voz en este dispositivo.');
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isSpeaking = false;
    });
  }

  Future<void> _setBestSpanishVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is! List) {
        return;
      }

      final parsedVoices = voices
          .whereType<Map>()
          .map(
            (voice) => voice.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();
      if (parsedVoices.isEmpty) {
        return;
      }

      final preferredSpanishVoice = parsedVoices.firstWhere(
        (voice) {
          final locale = (voice['locale'] ?? '').toString().toLowerCase();
          final name = (voice['name'] ?? '').toString().toLowerCase();
          return locale.startsWith('es') &&
              (name.contains('neural') ||
                  name.contains('premium') ||
                  name.contains('espa') ||
                  name.contains('spanish'));
        },
        orElse: () => parsedVoices.firstWhere(
          (voice) => (voice['locale'] ?? '')
              .toString()
              .toLowerCase()
              .startsWith('es'),
          orElse: () => <String, dynamic>{},
        ),
      );

      final locale = preferredSpanishVoice['locale']?.toString();
      final name = preferredSpanishVoice['name']?.toString();
      if (locale == null || locale.isEmpty || name == null || name.isEmpty) {
        return;
      }

      await _flutterTts.setVoice({
        'name': name,
        'locale': locale,
      });
    } catch (_) {
      // Fallback to setLanguage already configured above.
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final hasSpeech = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );

      _speechEnabled = hasSpeech;
      if (!_speechEnabled) {
        _spanishLocaleId = null;
        return;
      }

      final locales = await _speechToText.locales();
      _spanishLocaleId = _pickBestSpanishSpeechLocale(
        locales.map((locale) => locale.localeId).toList(),
      );
    } catch (_) {
      _speechEnabled = false;
      _spanishLocaleId = null;
    }
  }

  Future<bool> _ensureSpanishTtsVoice() async {
    final preferredTtsLanguage = await _pickBestSpanishTtsLanguage();
    if (preferredTtsLanguage == null) {
      return false;
    }
    await _flutterTts.setLanguage(preferredTtsLanguage);
    await _setBestSpanishVoice();
    return true;
  }

  Future<String?> _pickBestSpanishTtsLanguage() async {
    try {
      final languages = await _flutterTts.getLanguages;
      if (languages is! List) {
        return null;
      }
      final languageCodes = languages.map((value) => value.toString()).toList();
      return _pickPreferredSpanishCode(languageCodes);
    } catch (_) {
      return null;
    }
  }

  String? _pickBestSpanishSpeechLocale(List<String> localeIds) {
    return _pickPreferredSpanishCode(localeIds);
  }

  String? _pickPreferredSpanishCode(List<String> codes) {
    if (codes.isEmpty) {
      return null;
    }

    const preferredCodes = ['es-AR', 'es-ES', 'es-MX', 'es-US', 'es-419', 'es'];
    for (final preferred in preferredCodes) {
      for (final code in codes) {
        final normalizedCode = code.replaceAll('_', '-').toLowerCase();
        final normalizedPreferred = preferred.toLowerCase();
        if (normalizedCode == normalizedPreferred) {
          return code;
        }
      }
    }

    for (final code in codes) {
      if (code.replaceAll('_', '-').toLowerCase().startsWith('es')) {
        return code;
      }
    }

    return null;
  }

  Future<void> _stopListening({required bool discardResult}) async {
    _isStoppingListening = true;
    if (discardResult) {
      await _speechToText.cancel();
    } else {
      await _speechToText.stop();
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _voiceStatus = discardResult
          ? 'Micrófono detenido.'
          : 'Transcripción lista. Toca buscar versículo.';
    });
  }

  void _handleTopicChanged(String value) {
    if (value.trim().isNotEmpty) {
      return;
    }

    if (_lastTranscript.isEmpty &&
        _lastTopic.isEmpty &&
        !_isListening &&
        !_speechToText.isListening) {
      return;
    }

    _lastTranscript = '';
    _lastTopic = '';
    if (_isListening || _speechToText.isListening) {
      _stopListening(discardResult: true);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _voiceStatus = _speechEnabled
          ? 'Texto borrado. Puedes escribir o dictar un tema nuevo.'
          : 'Texto borrado. Puedes escribir un tema nuevo.';
    });
  }

  Future<void> _shareVerse() async {
    final verse = _selectedVerse;
    if (verse == null) {
      _showSnackBar('Genera un versículo antes de compartir.');
      return;
    }

    final message = _buildVerseShareText(verse);
    try {
      final imageBytes = await _buildVerseShareImageBytes(verse);
      if (imageBytes == null || imageBytes.isEmpty) {
        throw Exception('No se pudo generar la imagen del versículo.');
      }

      final imageFile = XFile.fromData(
        imageBytes,
        mimeType: 'image/png',
        name: 'versiculo-versovivo.png',
      );

      await Share.shareXFiles(
        [imageFile],
        text: message,
        subject: 'Versículo diario en $_appName',
      );
    } catch (_) {
      await Share.share(message, subject: 'Versículo diario en $_appName');
      _showSnackBar(
        'Compartí en texto porque no se pudo generar la imagen en este dispositivo.',
      );
    }
  }

  Future<void> _shareApp() async {
    final message = [
      'Estoy usando $_appName para recibir un versículo diario según mi tema.',
      'Web: $_webUrl',
      'Android: $_androidUrl',
      'iPhone: $_iosUrl',
    ].join('\n');

    await Share.share(message, subject: 'Te comparto $_appName');
  }

  String _buildVerseShareText(VerseCardData verse) {
    return [
      'Mi versículo de hoy en $_appName:',
      '"${verse.text}"',
      verse.reference,
      if (_lastTopic.isNotEmpty) 'Tema: $_lastTopic',
      'Web: $_webUrl',
    ].join('\n');
  }

  String _buildAppShareText() {
    return [
      'Estoy usando $_appName para recibir un versículo diario según mi tema.',
      'Web: $_webUrl',
      'Android: $_androidUrl',
      'iPhone: $_iosUrl',
    ].join('\n');
  }

  Future<Uint8List?> _buildVerseShareImageBytes(VerseCardData verse) async {
    const imageWidth = 1080.0;
    const imageHeight = 1350.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, imageWidth, imageHeight),
    );

    final backgroundPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(imageWidth, imageHeight),
        const [
          Color(0xFF1B7F6D),
          Color(0xFF226A78),
          Color(0xFFB28A39),
        ],
        const [0.0, 0.68, 1.0],
      );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, imageWidth, imageHeight),
      backgroundPaint,
    );

    final glowPaint = Paint()..color = const Color(0x66FFFFFF);
    canvas.drawCircle(const Offset(140, 120), 130, glowPaint);
    canvas.drawCircle(
      const Offset(920, 180),
      170,
      glowPaint..color = const Color(0x44FFF0D4),
    );

    final verseCardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(66, 238, 948, 760),
      const Radius.circular(44),
    );
    canvas.drawRRect(
      verseCardRect,
      Paint()..color = const Color(0xF9FFF8EF),
    );
    canvas.drawRRect(
      verseCardRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x4D1B7F6D),
    );

    _paintShareText(
      canvas: canvas,
      text: _appName,
      offset: const Offset(78, 70),
      maxWidth: 924,
      style: const TextStyle(
        fontSize: 60,
        fontWeight: FontWeight.w700,
        color: Color(0xFFFFF6EB),
      ),
    );
    _paintShareText(
      canvas: canvas,
      text: 'Versículo de hoy',
      offset: const Offset(82, 158),
      maxWidth: 920,
      style: const TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: Color(0xFFF0E9D9),
      ),
    );

    _paintShareText(
      canvas: canvas,
      text: '"${verse.text}"',
      offset: const Offset(120, 310),
      maxWidth: 840,
      style: const TextStyle(
        fontSize: 54,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: Color(0xFF183438),
      ),
      maxLines: 11,
    );
    _paintShareText(
      canvas: canvas,
      text: verse.reference,
      offset: const Offset(120, 915),
      maxWidth: 840,
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1B7F6D),
      ),
    );

    if (_lastTopic.isNotEmpty) {
      _paintShareText(
        canvas: canvas,
        text: 'Tema: $_lastTopic',
        offset: const Offset(120, 965),
        maxWidth: 840,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3A4C4E),
        ),
        maxLines: 2,
      );
    }

    final footerRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(66, 1060, 948, 220),
      const Radius.circular(30),
    );
    canvas.drawRRect(
      footerRect,
      Paint()..color = const Color(0x26FFFFFF),
    );
    _paintShareText(
      canvas: canvas,
      text: 'Comparte la app: $_webUrl',
      offset: const Offset(104, 1120),
      maxWidth: 880,
      style: const TextStyle(
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: Color(0xFFFFF6EB),
      ),
      maxLines: 3,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth.toInt(), imageHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  void _paintShareText({
    required Canvas canvas,
    required String text,
    required Offset offset,
    required double maxWidth,
    required TextStyle style,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  Future<void> _shareToSocialNetwork({
    required _SocialNetwork network,
    required bool shareVerse,
  }) async {
    final verse = _selectedVerse;
    if (shareVerse && verse == null) {
      _showSnackBar('Genera un versículo antes de compartir.');
      return;
    }

    final text = shareVerse ? _buildVerseShareText(verse!) : _buildAppShareText();
    final encodedText = Uri.encodeComponent(text);
    final encodedUrl = Uri.encodeComponent(_webUrl);
    final encodedImage = Uri.encodeComponent('$_webUrl/icons/Icon-512.png');

    if (network == _SocialNetwork.instagram) {
      await Share.share(
        text,
        subject: shareVerse ? 'Versículo diario en $_appName' : 'Te comparto $_appName',
      );
      _showSnackBar(
        'Instagram se comparte desde la ventana nativa de compartir.',
      );
      return;
    }

    final uri = switch (network) {
      _SocialNetwork.whatsapp =>
        Uri.parse('https://api.whatsapp.com/send?text=$encodedText'),
      _SocialNetwork.facebook => Uri.parse(
        'https://www.facebook.com/sharer/sharer.php?u=$encodedUrl&quote=$encodedText',
      ),
      _SocialNetwork.x =>
        Uri.parse('https://twitter.com/intent/tweet?text=$encodedText'),
      _SocialNetwork.linkedin => Uri.parse(
        'https://www.linkedin.com/sharing/share-offsite/?url=$encodedUrl',
      ),
      _SocialNetwork.pinterest => Uri.parse(
        'https://pinterest.com/pin/create/button/?url=$encodedUrl&media=$encodedImage&description=$encodedText',
      ),
      _SocialNetwork.instagram => null,
    };

    if (uri == null) {
      _showSnackBar('No pude generar el enlace de ${network.label}.');
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched) {
      _showSnackBar('No pude abrir ${network.label}.');
    }
  }

  Future<void> _copyVerse() async {
    final verse = _selectedVerse;
    if (verse == null) {
      _showSnackBar('Aún no hay versículo para copiar.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: '${verse.text} (${verse.reference})'),
    );
    _showSnackBar('Versículo copiado al portapapeles.');
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _topicController.dispose();
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFFAF2),
              Color(0xFFF7EEDB),
              Color(0xFFEAF5EF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -120,
              right: -80,
              child: _AuroraBlob(
                diameter: 360,
                colors: [
                  Color(0x66D6A23D),
                  Color(0x33D6A23D),
                  Color(0x00D6A23D),
                ],
              ),
            ),
            const Positioned(
              bottom: -180,
              left: -90,
              child: _AuroraBlob(
                diameter: 420,
                colors: [
                  Color(0x6684C9B4),
                  Color(0x3384C9B4),
                  Color(0x0084C9B4),
                ],
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 980;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildInputPanel()),
                              const SizedBox(width: 18),
                              Expanded(child: _buildVersePanel()),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            _buildInputPanel(),
                            const SizedBox(height: 14),
                            _buildVersePanel(),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (_showWelcomeOverlay) Positioned.fill(child: _buildWelcomeOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF102327).withOpacity(0.62),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _SoftPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bienvenidas',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF163437),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _welcomeMessage,
                    style: GoogleFonts.manrope(
                      fontSize: 15.5,
                      height: 1.45,
                      color: const Color(0xFF273537),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _showWelcomeOverlay = false;
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B7F6D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 13,
                        ),
                        textStyle: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    final textStyle = GoogleFonts.manrope(
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF334040),
    );

    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: const Color(0xFF1B7F6D).withOpacity(0.10),
              border: Border.all(color: const Color(0xFF1B7F6D).withOpacity(0.25)),
            ),
            child: Text(
              'VersoVivo • Versículo diario',
              style: GoogleFonts.manrope(
                fontSize: 12,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF145F50),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _appName,
            style: GoogleFonts.playfairDisplay(
              fontSize: 68,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF163437),
              height: 0.9,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Un espacio diario para respirar, escuchar y compartir un versículo con sentido.',
            style: textStyle,
          ),
          const SizedBox(height: 24),
          Text(
            _question,
            style: GoogleFonts.playfairDisplay(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF102327),
              height: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFFFFFFFF).withOpacity(0.72),
              border: Border.all(color: const Color(0xFF1B7F6D).withOpacity(0.20)),
            ),
            child: TextField(
              controller: _topicController,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.done,
              onChanged: _handleTopicChanged,
              onSubmitted: (_) => _buildVerseForTopic(),
              style: GoogleFonts.manrope(
                fontSize: 16,
                height: 1.3,
                color: const Color(0xFF132023),
              ),
              decoration: InputDecoration(
                hintText: 'Ejemplo: ansiedad, trabajo, familia, paz, salud...',
                hintStyle: GoogleFonts.manrope(
                  color: const Color(0xFF4D5A5B).withOpacity(0.72),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _isListening
                  ? const Color(0xFFFFF3DE)
                  : const Color(0xFFF3F7F4),
              border: Border.all(
                color: _isListening
                    ? const Color(0xFFB28A39).withOpacity(0.35)
                    : const Color(0xFF1B7F6D).withOpacity(0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isListening ? Icons.graphic_eq : Icons.info_outline_rounded,
                  size: 18,
                  color: _isListening
                      ? const Color(0xFF9A752F)
                      : const Color(0xFF2D5D58),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _voiceStatus,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      height: 1.35,
                      color: const Color(0xFF2A3838),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FilledButton(
                onPressed: _buildVerseForTopic,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B7F6D),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Buscar versículo'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleListening,
                icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                label: Text(_isListening ? 'Detener micrófono' : 'Hablar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1B4E58),
                  side: BorderSide(color: const Color(0xFF1B4E58).withOpacity(0.35)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSpeaking ? _stopSpeaking : _speakSelectedVerse,
                icon: Icon(_isSpeaking ? Icons.stop_circle : Icons.volume_up),
                label: Text(_isSpeaking ? 'Detener voz' : 'Escuchar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6D4F1E),
                  side: BorderSide(color: const Color(0xFF6D4F1E).withOpacity(0.30)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Temas rápidos',
            style: GoogleFonts.manrope(
              color: const Color(0xFF2E3F42),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickTopics.map((topic) {
              return ActionChip(
                label: Text(topic),
                labelStyle: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2A4447),
                ),
                side: BorderSide(color: const Color(0xFF1B7F6D).withOpacity(0.20)),
                backgroundColor: const Color(0xFFFFFFFF).withOpacity(0.75),
                onPressed: () {
                  _topicController.text = topic;
                  _topicController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _topicController.text.length),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVersePanel() {
    return _SoftPanel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _selectedVerse == null
            ? _buildEmptyVerseState()
            : _buildGeneratedVerseState(_selectedVerse!),
      ),
    );
  }

  Widget _buildEmptyVerseState() {
    return SizedBox(
      key: const ValueKey('empty'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1B7F6D).withOpacity(0.14),
              border: Border.all(color: const Color(0xFF1B7F6D).withOpacity(0.24)),
            ),
            child: const Icon(
              Icons.auto_stories_outlined,
              size: 28,
              color: Color(0xFF1B5E53),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tu versículo aparecerá aquí',
            style: GoogleFonts.playfairDisplay(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A3338),
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Escribe o dicta el tema y elige un versículo de aproximadamente 30 palabras para hoy.',
            style: GoogleFonts.manrope(
              fontSize: 15,
              color: const Color(0xFF3F4A4C),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFFFFFFFF).withOpacity(0.72),
              border: Border.all(color: const Color(0xFF7AB7A8).withOpacity(0.28)),
            ),
            child: Text(
              'Tip: usa el botón Hablar para dictar tu tema en español y toca Buscar versículo para generar el resultado.',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: const Color(0xFF355052),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedVerseState(VerseCardData verse) {
    return SizedBox(
      key: ValueKey(verse.reference + _lastTopic),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versículo de hoy',
            style: GoogleFonts.manrope(
              color: const Color(0xFF2B4A4D),
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1B7F6D),
                  Color(0xFF226A78),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF214E56).withOpacity(0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${verse.text}"',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 35,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFF6EB),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  verse.reference,
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFE8F6F2),
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
          if (_lastTopic.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Tema detectado: $_lastTopic',
              style: GoogleFonts.manrope(
                color: const Color(0xFF385255),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              FilledButton.icon(
                onPressed: _shareVerse,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB28A39),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(
                  'Comparte este versículo',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _shareApp,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A5963),
                  side: BorderSide(color: const Color(0xFF1A5963).withOpacity(0.32)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  'Comparte la app',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _copyVerse,
                icon: const Icon(Icons.copy_rounded),
                label: Text(
                  'Copiar',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Compartir versículo en',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4B5B5D),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _SocialNetwork.values
                .map(
                  (network) => _SocialShareChip(
                    label: network.label,
                    iconData: network.iconData,
                    iconColor: network.iconColor,
                    onPressed: () => _shareToSocialNetwork(
                      network: network,
                      shareVerse: true,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Text(
            'Compartir app en',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4B5B5D),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _SocialNetwork.values
                .map(
                  (network) => _SocialShareChip(
                    label: network.label,
                    iconData: network.iconData,
                    iconColor: network.iconColor,
                    onPressed: () => _shareToSocialNetwork(
                      network: network,
                      shareVerse: false,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _AuroraBlob extends StatelessWidget {
  const _AuroraBlob({
    required this.diameter,
    required this.colors,
  });

  final double diameter;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.94, end: 1.0),
      builder: (context, value, content) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: content,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: const Color(0xFFFFFEFB).withOpacity(0.78),
          border: Border.all(color: const Color(0xFFB9C9BE).withOpacity(0.38)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9AAB9D).withOpacity(0.24),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

enum _SocialNetwork {
  whatsapp('WhatsApp', FontAwesomeIcons.whatsapp, Color(0xFF25D366)),
  instagram('Instagram', FontAwesomeIcons.instagram, Color(0xFFE4405F)),
  facebook('Facebook', FontAwesomeIcons.facebookF, Color(0xFF1877F2)),
  x('X', FontAwesomeIcons.xTwitter, Color(0xFF111111)),
  linkedin('LinkedIn', FontAwesomeIcons.linkedinIn, Color(0xFF0A66C2)),
  pinterest('Pinterest', FontAwesomeIcons.pinterestP, Color(0xFFE60023));

  const _SocialNetwork(this.label, this.iconData, this.iconColor);
  final String label;
  final IconData iconData;
  final Color iconColor;
}

class _SocialShareChip extends StatelessWidget {
  const _SocialShareChip({
    required this.label,
    required this.iconData,
    required this.iconColor,
    required this.onPressed,
  });

  final String label;
  final IconData iconData;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: const Color(0xFF29484A),
        side: BorderSide(color: const Color(0xFF29484A).withOpacity(0.25)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(iconData, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class VerseCardData {
  const VerseCardData({
    required this.reference,
    required this.text,
    required this.keywords,
  });

  final String reference;
  final String text;
  final List<String> keywords;
}

class _BibleParsedReference {
  const _BibleParsedReference({
    required this.bookId,
    required this.bookName,
    this.chapter,
    this.verseStart,
    this.verseEnd,
  });

  final String bookId;
  final String bookName;
  final int? chapter;
  final int? verseStart;
  final int? verseEnd;
}

class _BibleBookDefinition {
  const _BibleBookDefinition({
    required this.id,
    required this.name,
    required this.aliases,
  });

  final String id;
  final String name;
  final List<String> aliases;
}

const List<_BibleBookDefinition> _bibleBooks = [
  _BibleBookDefinition(
    id: 'gn',
    name: 'Génesis',
    aliases: ['genesis', 'gen'],
  ),
  _BibleBookDefinition(
    id: 'ex',
    name: 'Éxodo',
    aliases: ['exodo', 'exo', 'ex'],
  ),
  _BibleBookDefinition(
    id: 'lv',
    name: 'Levítico',
    aliases: ['levitico', 'levit', 'lev'],
  ),
  _BibleBookDefinition(
    id: 'nm',
    name: 'Números',
    aliases: ['numeros', 'num'],
  ),
  _BibleBookDefinition(
    id: 'dt',
    name: 'Deuteronomio',
    aliases: ['deuteronomio', 'deut', 'dt'],
  ),
  _BibleBookDefinition(
    id: 'js',
    name: 'Josué',
    aliases: ['josue', 'jos'],
  ),
  _BibleBookDefinition(
    id: 'jd',
    name: 'Jueces',
    aliases: ['jueces', 'juez'],
  ),
  _BibleBookDefinition(
    id: 'rt',
    name: 'Rut',
    aliases: ['rut', 'rt'],
  ),
  _BibleBookDefinition(
    id: '1sm',
    name: '1 Samuel',
    aliases: [
      '1 samuel',
      '1samuel',
      'primer samuel',
      'primera de samuel',
      'primera samuel',
    ],
  ),
  _BibleBookDefinition(
    id: '2sm',
    name: '2 Samuel',
    aliases: [
      '2 samuel',
      '2samuel',
      'segundo samuel',
      'segunda de samuel',
      'segunda samuel',
    ],
  ),
  _BibleBookDefinition(
    id: '1kgs',
    name: '1 Reyes',
    aliases: [
      '1 reyes',
      '1reyes',
      'primer reyes',
      'primera de reyes',
      'primera reyes',
    ],
  ),
  _BibleBookDefinition(
    id: '2kgs',
    name: '2 Reyes',
    aliases: [
      '2 reyes',
      '2reyes',
      'segundo reyes',
      'segunda de reyes',
      'segunda reyes',
    ],
  ),
  _BibleBookDefinition(
    id: '1ch',
    name: '1 Crónicas',
    aliases: [
      '1 cronicas',
      '1cronicas',
      'primer cronicas',
      'primera de cronicas',
      'primera cronicas',
    ],
  ),
  _BibleBookDefinition(
    id: '2ch',
    name: '2 Crónicas',
    aliases: [
      '2 cronicas',
      '2cronicas',
      'segundo cronicas',
      'segunda de cronicas',
      'segunda cronicas',
    ],
  ),
  _BibleBookDefinition(
    id: 'ezr',
    name: 'Esdras',
    aliases: ['esdras', 'ezr'],
  ),
  _BibleBookDefinition(
    id: 'ne',
    name: 'Nehemías',
    aliases: ['nehemias', 'neh', 'ne'],
  ),
  _BibleBookDefinition(
    id: 'et',
    name: 'Ester',
    aliases: ['ester', 'est'],
  ),
  _BibleBookDefinition(
    id: 'job',
    name: 'Job',
    aliases: ['job'],
  ),
  _BibleBookDefinition(
    id: 'ps',
    name: 'Salmos',
    aliases: ['salmo', 'salmos', 'ps'],
  ),
  _BibleBookDefinition(
    id: 'prv',
    name: 'Proverbios',
    aliases: ['proverbios', 'proverbio', 'prov', 'prv'],
  ),
  _BibleBookDefinition(
    id: 'ec',
    name: 'Eclesiastés',
    aliases: ['eclesiastes', 'ecle', 'ec'],
  ),
  _BibleBookDefinition(
    id: 'so',
    name: 'Cantares',
    aliases: [
      'cantares',
      'cantar de los cantares',
      'cantar',
      'cantares de salomon',
    ],
  ),
  _BibleBookDefinition(
    id: 'is',
    name: 'Isaías',
    aliases: ['isaias', 'isa'],
  ),
  _BibleBookDefinition(
    id: 'jr',
    name: 'Jeremías',
    aliases: ['jeremias', 'jer'],
  ),
  _BibleBookDefinition(
    id: 'lm',
    name: 'Lamentaciones',
    aliases: ['lamentaciones', 'lam'],
  ),
  _BibleBookDefinition(
    id: 'ez',
    name: 'Ezequiel',
    aliases: ['ezequiel', 'eze'],
  ),
  _BibleBookDefinition(
    id: 'dn',
    name: 'Daniel',
    aliases: ['daniel', 'dan', 'dn'],
  ),
  _BibleBookDefinition(
    id: 'ho',
    name: 'Oseas',
    aliases: ['oseas', 'os'],
  ),
  _BibleBookDefinition(
    id: 'jl',
    name: 'Joel',
    aliases: ['joel', 'jl'],
  ),
  _BibleBookDefinition(
    id: 'am',
    name: 'Amós',
    aliases: ['amos', 'am'],
  ),
  _BibleBookDefinition(
    id: 'ob',
    name: 'Abdías',
    aliases: ['abdias', 'abd', 'ob'],
  ),
  _BibleBookDefinition(
    id: 'jn',
    name: 'Jonás',
    aliases: ['jonas', 'jon'],
  ),
  _BibleBookDefinition(
    id: 'mi',
    name: 'Miqueas',
    aliases: ['miqueas', 'miq', 'mi'],
  ),
  _BibleBookDefinition(
    id: 'na',
    name: 'Nahum',
    aliases: ['nahum', 'na'],
  ),
  _BibleBookDefinition(
    id: 'hk',
    name: 'Habacuc',
    aliases: ['habacuc', 'hab', 'hk'],
  ),
  _BibleBookDefinition(
    id: 'zp',
    name: 'Sofonías',
    aliases: ['sofonias', 'sof', 'zp'],
  ),
  _BibleBookDefinition(
    id: 'hg',
    name: 'Hageo',
    aliases: ['hageo', 'hag', 'hg'],
  ),
  _BibleBookDefinition(
    id: 'zc',
    name: 'Zacarías',
    aliases: ['zacarias', 'zac', 'zc'],
  ),
  _BibleBookDefinition(
    id: 'ml',
    name: 'Malaquías',
    aliases: ['malaquias', 'mal', 'ml'],
  ),
  _BibleBookDefinition(
    id: 'mt',
    name: 'Mateo',
    aliases: ['mateo', 'mat', 'mt'],
  ),
  _BibleBookDefinition(
    id: 'mk',
    name: 'Marcos',
    aliases: ['marcos', 'mr', 'mk'],
  ),
  _BibleBookDefinition(
    id: 'lk',
    name: 'Lucas',
    aliases: ['lucas', 'luc', 'lk'],
  ),
  _BibleBookDefinition(
    id: 'jo',
    name: 'Juan',
    aliases: ['juan', 'san juan', 'evangelio de juan'],
  ),
  _BibleBookDefinition(
    id: 'act',
    name: 'Hechos',
    aliases: ['hechos', 'hechos de los apostoles', 'act'],
  ),
  _BibleBookDefinition(
    id: 'rm',
    name: 'Romanos',
    aliases: ['romanos', 'rom', 'rm'],
  ),
  _BibleBookDefinition(
    id: '1co',
    name: '1 Corintios',
    aliases: [
      '1 corintios',
      '1corintios',
      '1 corintos',
      '1corintos',
      'primer corintios',
      'primera de corintios',
      'primera corintios',
    ],
  ),
  _BibleBookDefinition(
    id: '2co',
    name: '2 Corintios',
    aliases: [
      '2 corintios',
      '2corintios',
      '2 corintos',
      '2corintos',
      'segundo corintios',
      'segunda de corintios',
      'segunda corintios',
    ],
  ),
  _BibleBookDefinition(
    id: 'gl',
    name: 'Gálatas',
    aliases: ['galatas', 'gal', 'gl'],
  ),
  _BibleBookDefinition(
    id: 'eph',
    name: 'Efesios',
    aliases: ['efesios', 'efe', 'eph'],
  ),
  _BibleBookDefinition(
    id: 'ph',
    name: 'Filipenses',
    aliases: ['filipenses', 'fil', 'ph'],
  ),
  _BibleBookDefinition(
    id: 'cl',
    name: 'Colosenses',
    aliases: ['colosenses', 'col', 'cl'],
  ),
  _BibleBookDefinition(
    id: '1ts',
    name: '1 Tesalonicenses',
    aliases: [
      '1 tesalonicenses',
      '1tesalonicenses',
      'primer tesalonicenses',
      'primera de tesalonicenses',
      'primera tesalonicenses',
    ],
  ),
  _BibleBookDefinition(
    id: '2ts',
    name: '2 Tesalonicenses',
    aliases: [
      '2 tesalonicenses',
      '2tesalonicenses',
      'segundo tesalonicenses',
      'segunda de tesalonicenses',
      'segunda tesalonicenses',
    ],
  ),
  _BibleBookDefinition(
    id: '1tm',
    name: '1 Timoteo',
    aliases: [
      '1 timoteo',
      '1timoteo',
      'primer timoteo',
      'primera de timoteo',
      'primera timoteo',
    ],
  ),
  _BibleBookDefinition(
    id: '2tm',
    name: '2 Timoteo',
    aliases: [
      '2 timoteo',
      '2timoteo',
      'segundo timoteo',
      'segunda de timoteo',
      'segunda timoteo',
    ],
  ),
  _BibleBookDefinition(
    id: 'tt',
    name: 'Tito',
    aliases: ['tito', 'tt'],
  ),
  _BibleBookDefinition(
    id: 'phm',
    name: 'Filemón',
    aliases: ['filemon', 'flm', 'phm'],
  ),
  _BibleBookDefinition(
    id: 'hb',
    name: 'Hebreos',
    aliases: ['hebreos', 'heb', 'hb'],
  ),
  _BibleBookDefinition(
    id: 'jm',
    name: 'Santiago',
    aliases: ['santiago', 'stg', 'jm'],
  ),
  _BibleBookDefinition(
    id: '1pe',
    name: '1 Pedro',
    aliases: [
      '1 pedro',
      '1pedro',
      'primer pedro',
      'primera de pedro',
      'primera pedro',
    ],
  ),
  _BibleBookDefinition(
    id: '2pe',
    name: '2 Pedro',
    aliases: [
      '2 pedro',
      '2pedro',
      'segundo pedro',
      'segunda de pedro',
      'segunda pedro',
    ],
  ),
  _BibleBookDefinition(
    id: '1jo',
    name: '1 Juan',
    aliases: [
      '1 juan',
      '1juan',
      'primer juan',
      'primera de juan',
      'primera juan',
      'primera carta de juan',
      'carta de juan',
      'epistola de juan',
    ],
  ),
  _BibleBookDefinition(
    id: '2jo',
    name: '2 Juan',
    aliases: [
      '2 juan',
      '2juan',
      'segundo juan',
      'segunda de juan',
      'segunda juan',
      'segunda carta de juan',
    ],
  ),
  _BibleBookDefinition(
    id: '3jo',
    name: '3 Juan',
    aliases: [
      '3 juan',
      '3juan',
      'tercer juan',
      'tercera de juan',
      'tercera juan',
      'tercera carta de juan',
    ],
  ),
  _BibleBookDefinition(
    id: 'jud',
    name: 'Judas',
    aliases: ['judas', 'jud'],
  ),
  _BibleBookDefinition(
    id: 're',
    name: 'Apocalipsis',
    aliases: ['apocalipsis', 'revelacion', 'revelaciones', 're'],
  ),
];

const List<String> _quickTopics = [
  'ansiedad',
  'fortaleza',
  'familia',
  'dirección',
  'duelo',
  'gratitud',
  'trabajo',
  'descanso',
];

const List<VerseCardData> _verseCatalog = [
  VerseCardData(
    reference: 'Salmo 23:1-3',
    text:
        'El Señor es mi pastor; nada me faltará. En verdes pastos me hace descansar, junto a aguas tranquilas me conduce y reconforta mi alma para seguir adelante.',
    keywords: ['ansiedad', 'descanso', 'paz', 'agotado', 'cansado', 'estrés'],
  ),
  VerseCardData(
    reference: 'Salmo 1:1-3',
    text:
        'Bienaventurado quien se deleita en la ley del Señor y en ella medita de día y de noche; será como árbol plantado junto a corrientes de agua, que da fruto a su tiempo y su hoja no cae.',
    keywords: ['salmo 1', 'meditar', 'firmeza', 'raices', 'fruto'],
  ),
  VerseCardData(
    reference: 'Salmo 34:18',
    text:
        'Cercano está el Señor a los quebrantados de corazón, y salva a los de espíritu abatido cuando sienten que ya no tienen fuerzas para continuar.',
    keywords: ['duelo', 'tristeza', 'dolor', 'pérdida', 'depresión', 'soledad'],
  ),
  VerseCardData(
    reference: 'Filipenses 4:6-7',
    text:
        'No se inquieten por nada; presenten sus peticiones a Dios con oración y gratitud, y su paz guardará su mente y su corazón en Cristo Jesús.',
    keywords: ['ansiedad', 'miedo', 'preocupación', 'pánico', 'calma'],
  ),
  VerseCardData(
    reference: 'Isaías 41:10',
    text:
        'No temas, porque yo estoy contigo; no desmayes, porque yo soy tu Dios que te fortalece, te ayuda y te sostiene con mi mano firme y fiel.',
    keywords: ['fortaleza', 'miedo', 'trabajo', 'incertidumbre', 'inseguridad'],
  ),
  VerseCardData(
    reference: 'Salmo 121:1-2',
    text:
        'Alzo mis ojos a los montes: ¿de dónde vendrá mi ayuda? Mi ayuda viene del Señor, creador del cielo y de la tierra, hoy y siempre.',
    keywords: ['ayuda', 'dirección', 'decisiones', 'guía', 'rumbo'],
  ),
  VerseCardData(
    reference: 'Proverbios 3:5-6',
    text:
        'Confía en el Señor con todo tu corazón y no te apoyes en tu propia prudencia; reconócelo en tus caminos y él enderezará tus sendas.',
    keywords: ['dirección', 'decisiones', 'futuro', 'trabajo', 'proyecto'],
  ),
  VerseCardData(
    reference: 'Mateo 11:28',
    text:
        'Vengan a mí todos los que están cansados y cargados, y yo les daré descanso; en mí hallarán alivio para el alma en medio del peso diario.',
    keywords: ['cansancio', 'agotado', 'estrés', 'descanso', 'sobrecarga'],
  ),
  VerseCardData(
    reference: 'Josué 1:9',
    text:
        'Sé fuerte y valiente; no temas ni desmayes, porque el Señor tu Dios estará contigo dondequiera que vayas y en cada paso de tu camino.',
    keywords: ['fortaleza', 'valentía', 'empezar', 'nuevo', 'retos', 'miedo'],
  ),
  VerseCardData(
    reference: 'Romanos 8:28',
    text:
        'Sabemos que Dios dispone todas las cosas para bien de quienes le aman, aun cuando hoy no entiendan el proceso completo que están viviendo.',
    keywords: ['esperanza', 'proceso', 'frustración', 'duelo', 'crisis'],
  ),
  VerseCardData(
    reference: '1 Corintios 3:16',
    text:
        '¿No saben que ustedes son templo de Dios y que el Espíritu de Dios habita en ustedes? Vivan recordando ese valor santo que Dios les dio.',
    keywords: ['corintios 3', 'corintos 3', 'identidad', 'espiritu santo'],
  ),
  VerseCardData(
    reference: 'Salmo 127:1',
    text:
        'Si el Señor no edifica la casa, en vano trabajan los que la construyen; encomienda tu proyecto y tu familia para que tenga fundamento firme.',
    keywords: ['familia', 'hogar', 'trabajo', 'negocio', 'proyecto'],
  ),
  VerseCardData(
    reference: 'Salmo 100:4',
    text:
        'Entren por sus puertas con acción de gracias y por sus atrios con alabanza; denle gracias y bendigan su nombre por cada detalle recibido.',
    keywords: ['gratitud', 'agradecimiento', 'alegría', 'gozo'],
  ),
  VerseCardData(
    reference: 'Salmo 46:1',
    text:
        'Dios es nuestro amparo y fortaleza, nuestro pronto auxilio en las tribulaciones; por eso no temeremos aunque todo alrededor parezca inestable.',
    keywords: ['crisis', 'miedo', 'caos', 'fortaleza', 'problemas'],
  ),
];

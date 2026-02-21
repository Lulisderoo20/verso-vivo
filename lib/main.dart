import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD8B46A),
        secondary: Color(0xFF67C7BB),
        surface: Color(0xFF111A28),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VersoVivo',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(baseTheme.textTheme),
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
      'Sobre que quieres que trate el versiculo de hoy?';
  static const String _webUrl = 'https://verso-vivo.pages.dev';
  static const String _androidUrl =
      'https://play.google.com/store/apps/details?id=com.usuario.verso_vivo';
  static const String _iosUrl = 'https://apps.apple.com/app/id0000000000';

  final TextEditingController _topicController = TextEditingController();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final Random _random = Random();

  VerseCardData? _selectedVerse;
  String _voiceStatus = 'Escribe o usa el microfono para contar tu tema.';
  String _lastTopic = '';
  String? _spanishLocaleId;
  String _lastTranscript = '';
  bool _isStoppingListening = false;
  bool _ttsReady = false;
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isSpeaking = false;

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
            'Microfono listo. Habla o escribe y luego toca buscar.';
      } else {
        _voiceStatus =
            'Microfono no disponible aqui. Verifica permiso de microfono en Chrome.';
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
        _voiceStatus = 'Transcripcion lista. Toca buscar versiculo.';
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
          'No entendi el audio con claridad. Puedes intentar otra vez.';
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechEnabled) {
      await _initializeSpeech();
    }

    if (!_speechEnabled) {
      _showSnackBar(
        'El reconocimiento de voz no esta disponible. Habilita el microfono en Chrome.',
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
          ? 'Transcripcion lista. Toca buscar versiculo.'
          : 'Escuchando...';
    });
  }

  Future<void> _buildVerseForTopic() async {
    if (_isListening || _speechToText.isListening) {
      await _stopListening(discardResult: false);
    }

    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showSnackBar('Primero escribe o dicta el tema del versiculo.');
      return;
    }

    final verse = _pickVerse(topic);
    setState(() {
      _selectedVerse = verse;
      _lastTopic = topic;
    });

    await _speak(
      'Sobre $topic, este es tu versiculo de hoy. ${verse.text}. ${verse.reference}.',
    );
  }

  VerseCardData _pickVerse(String topic) {
    final normalizedTopic = _normalize(topic);
    final scoredMatches = <MapEntry<VerseCardData, int>>[];

    for (final verse in _verseCatalog) {
      var score = 0;
      for (final keyword in verse.keywords) {
        if (normalizedTopic.contains(keyword)) {
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
      _showSnackBar('Aun no hay versiculo para leer.');
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
          'No hay voz en espanol disponible en este navegador.',
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
          ? 'Microfono detenido.'
          : 'Transcripcion lista. Toca buscar versiculo.';
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
      _showSnackBar('Genera un versiculo antes de compartir.');
      return;
    }

    final message = [
      'Mi versiculo de hoy en $_appName:',
      '"${verse.text}"',
      verse.reference,
      '',
      'Tema de hoy: $_lastTopic',
      'Comparte la app: $_webUrl',
    ].join('\n');

    await Share.share(message, subject: 'Versiculo diario en $_appName');
  }

  Future<void> _shareApp() async {
    final message = [
      'Estoy usando $_appName para recibir un versiculo diario segun mi tema.',
      'Web: $_webUrl',
      'Android: $_androidUrl',
      'iPhone: $_iosUrl',
    ].join('\n');

    await Share.share(message, subject: 'Te comparto $_appName');
  }

  Future<void> _copyVerse() async {
    final verse = _selectedVerse;
    if (verse == null) {
      _showSnackBar('Aun no hay versiculo para copiar.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: '${verse.text} (${verse.reference})'),
    );
    _showSnackBar('Versiculo copiado al portapapeles.');
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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF08131C),
              Color(0xFF112236),
              Color(0xFF1A3144),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -120,
                left: -80,
                child: _GlowOrb(
                  diameter: 320,
                  color: const Color(0xFF67C7BB).withOpacity(0.16),
                ),
              ),
              Positioned(
                bottom: -160,
                right: -90,
                child: _GlowOrb(
                  diameter: 380,
                  color: const Color(0xFFD8B46A).withOpacity(0.18),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 980;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildInputPanel()),
                              const SizedBox(width: 22),
                              Expanded(child: _buildVersePanel()),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            _buildInputPanel(),
                            const SizedBox(height: 18),
                            _buildVersePanel(),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputPanel() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _appName,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 58,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF9F2DA),
              height: 0.95,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tu espacio diario para escuchar, leer y compartir Palabra.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 26),
          Text(
            _question,
            style: GoogleFonts.cormorantGaramond(
              fontSize: 35,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topicController,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
            onChanged: _handleTopicChanged,
            onSubmitted: (_) => _buildVerseForTopic(),
            decoration: InputDecoration(
              hintText: 'Ejemplo: ansiedad, trabajo, familia, paz, salud...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
              filled: true,
              fillColor: const Color(0xFF0B1722).withOpacity(0.7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.14)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: Color(0xFFD8B46A), width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _voiceStatus,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.72),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _buildVerseForTopic,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Buscar versiculo'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleListening,
                icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                label: Text(_isListening ? 'Detener microfono' : 'Hablar'),
              ),
              OutlinedButton.icon(
                onPressed: _isSpeaking ? _stopSpeaking : _speakSelectedVerse,
                icon: Icon(_isSpeaking ? Icons.stop_circle : Icons.volume_up),
                label: Text(_isSpeaking ? 'Detener voz' : 'Escuchar'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Temas rapidos',
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickTopics.map((topic) {
              return ActionChip(
                label: Text(topic),
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
    return _GlassPanel(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
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
          Icon(
            Icons.menu_book_rounded,
            size: 44,
            color: const Color(0xFFD8B46A).withOpacity(0.95),
          ),
          const SizedBox(height: 14),
          Text(
            'Tu versiculo aparecera aqui',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Escribe o dicta el tema y elige un versiculo de aproximadamente 30 palabras para hoy.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.72),
              height: 1.35,
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
            'Versiculo de hoy',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '"${verse.text}"',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 34,
              height: 1.06,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFF8F2DD),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            verse.reference,
            style: TextStyle(
              color: const Color(0xFF6DD4C3).withOpacity(0.95),
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          if (_lastTopic.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tema detectado: $_lastTopic',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _shareVerse,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Comparte este versiculo con tus amigos'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _shareApp,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Comparte la app con tus amig@s'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _copyVerse,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar versiculo'),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.diameter,
    required this.color,
  });

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.92, end: 1.0),
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
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: const Color(0xFF0D1A28).withOpacity(0.76),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF01050B).withOpacity(0.45),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: child,
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

const List<String> _quickTopics = [
  'ansiedad',
  'fortaleza',
  'familia',
  'direccion',
  'duelo',
  'gratitud',
  'trabajo',
  'descanso',
];

const List<VerseCardData> _verseCatalog = [
  VerseCardData(
    reference: 'Salmo 23:1-3',
    text:
        'El Senor es mi pastor; nada me faltara. En verdes pastos me hace descansar, junto a aguas tranquilas me conduce y reconforta mi alma para seguir adelante.',
    keywords: ['ansiedad', 'descanso', 'paz', 'agotado', 'cansado', 'estres'],
  ),
  VerseCardData(
    reference: 'Salmo 34:18',
    text:
        'Cercano esta el Senor a los quebrantados de corazon, y salva a los de espiritu abatido cuando sienten que ya no tienen fuerzas para continuar.',
    keywords: ['duelo', 'tristeza', 'dolor', 'perdida', 'depresion', 'soledad'],
  ),
  VerseCardData(
    reference: 'Filipenses 4:6-7',
    text:
        'No se inquieten por nada; presenten sus peticiones a Dios con oracion y gratitud, y su paz guardara su mente y su corazon en Cristo Jesus.',
    keywords: ['ansiedad', 'miedo', 'preocupacion', 'panico', 'calma'],
  ),
  VerseCardData(
    reference: 'Isaias 41:10',
    text:
        'No temas, porque yo estoy contigo; no desmayes, porque yo soy tu Dios que te fortalece, te ayuda y te sostiene con mi mano firme y fiel.',
    keywords: ['fortaleza', 'miedo', 'trabajo', 'incertidumbre', 'inseguridad'],
  ),
  VerseCardData(
    reference: 'Salmo 121:1-2',
    text:
        'Alzo mis ojos a los montes: de donde vendra mi ayuda? Mi ayuda viene del Senor, creador del cielo y de la tierra, hoy y siempre.',
    keywords: ['ayuda', 'direccion', 'decisiones', 'guia', 'rumbo'],
  ),
  VerseCardData(
    reference: 'Proverbios 3:5-6',
    text:
        'Confia en el Senor con todo tu corazon y no te apoyes en tu propia prudencia; reconocelo en tus caminos y el enderezara tus sendas.',
    keywords: ['direccion', 'decisiones', 'futuro', 'trabajo', 'proyecto'],
  ),
  VerseCardData(
    reference: 'Mateo 11:28',
    text:
        'Vengan a mi todos los que estan cansados y cargados, y yo les dare descanso; en mi hallaran alivio para el alma en medio del peso diario.',
    keywords: ['cansancio', 'agotado', 'estres', 'descanso', 'sobrecarga'],
  ),
  VerseCardData(
    reference: 'Josue 1:9',
    text:
        'Se fuerte y valiente; no temas ni desmayes, porque el Senor tu Dios estara contigo dondequiera que vayas y en cada paso de tu camino.',
    keywords: ['fortaleza', 'valentia', 'empezar', 'nuevo', 'retos', 'miedo'],
  ),
  VerseCardData(
    reference: 'Romanos 8:28',
    text:
        'Sabemos que Dios dispone todas las cosas para bien de quienes le aman, aun cuando hoy no entiendan el proceso completo que estan viviendo.',
    keywords: ['esperanza', 'proceso', 'frustracion', 'duelo', 'crisis'],
  ),
  VerseCardData(
    reference: 'Salmo 127:1',
    text:
        'Si el Senor no edifica la casa, en vano trabajan los que la construyen; encomienda tu proyecto y tu familia para que tenga fundamento firme.',
    keywords: ['familia', 'hogar', 'trabajo', 'negocio', 'proyecto'],
  ),
  VerseCardData(
    reference: 'Salmo 100:4',
    text:
        'Entren por sus puertas con accion de gracias y por sus atrios con alabanza; denle gracias y bendigan su nombre por cada detalle recibido.',
    keywords: ['gratitud', 'agradecimiento', 'alegria', 'gozo'],
  ),
  VerseCardData(
    reference: 'Salmo 46:1',
    text:
        'Dios es nuestro amparo y fortaleza, nuestro pronto auxilio en las tribulaciones; por eso no temeremos aunque todo alrededor parezca inestable.',
    keywords: ['crisis', 'miedo', 'caos', 'fortaleza', 'problemas'],
  ),
];

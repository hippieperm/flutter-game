import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const NeonRunnerApp());
}

class NeonRunnerApp extends StatelessWidget {
  const NeonRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Neon Run',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'monospace',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purpleAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const NeonRunnerPage(),
    );
  }
}

class NeonRunnerPage extends StatefulWidget {
  const NeonRunnerPage({super.key});

  @override
  State<NeonRunnerPage> createState() => _NeonRunnerPageState();
}

class _NeonRunnerPageState extends State<NeonRunnerPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastTick;
  Size? _screenSize;

  final Random _rand = Random();
  final List<_Sparkle> _sparkles = [];
  final List<_Obstacle> _obstacles = [];

  double _playerX = 0.5; // 0~1 normalized
  double _score = 0;
  double _bestScore = 0;

  bool _isRunning = false;
  bool _isGameOver = false;

  double _spawnTimer = 0;
  static const double _playerRadius = 26;

  @override
  void initState() {
    super.initState();
    _initSparkles();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _initSparkles() {
    _sparkles.clear();
    for (int i = 0; i < 90; i++) {
      _sparkles.add(
        _Sparkle(
          x: _rand.nextDouble(),
          y: _rand.nextDouble(),
          speed: 18 + _rand.nextDouble() * 26,
          size: 1 + _rand.nextDouble() * 2.4,
          hue: _rand.nextDouble() * 360,
        ),
      );
    }
  }

  void _startGame() {
    setState(() {
      _obstacles.clear();
      _score = 0;
      _spawnTimer = 0;
      _playerX = 0.5;
      _isRunning = true;
      _isGameOver = false;
    });
  }

  void _endGame() {
    setState(() {
      _isRunning = false;
      _isGameOver = true;
      _bestScore = max(_bestScore, _score);
    });
  }

  void _onTick(Duration now) {
    final double dt = _lastTick == null
        ? 0
        : (now - _lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    if (!_isRunning || _screenSize == null || dt <= 0) return;

    _updateSparkles(dt);
    _updateObstacles(dt);
    _score += dt * 10;

    final bool hit = _checkCollision();
    if (hit) {
      _endGame();
      return;
    }

    setState(() {});
  }

  void _updateSparkles(double dt) {
    final height = _screenSize!.height;
    for (final s in _sparkles) {
      s.y += (s.speed * dt) / height;
      if (s.y > 1) {
        s
          ..y = 0
          ..x = _rand.nextDouble()
          ..hue = _rand.nextDouble() * 360
          ..speed = 18 + _rand.nextDouble() * 26;
      }
    }
  }

  void _updateObstacles(double dt) {
    final size = _screenSize!;
    _spawnTimer += dt;
    final spawnInterval = max(0.55, 1.2 - _score / 400); // faster over time

    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      _obstacles.add(
        _Obstacle(
          x: 0.1 + _rand.nextDouble() * 0.8,
          y: -50,
          size: 36 + _rand.nextDouble() * 26,
          speed: 180 + _rand.nextDouble() * 120 + _score * 0.4,
          hue: _rand.nextDouble() * 360,
        ),
      );
    }

    _obstacles.removeWhere((o) {
      o.y += o.speed * dt;
      return o.y - o.size > size.height;
    });
  }

  bool _checkCollision() {
    final size = _screenSize!;
    final playerCenter = Offset(_playerX * size.width, size.height * 0.82);

    for (final o in _obstacles) {
      final obstacleCenter = Offset(o.x * size.width, o.y);
      final distance = (playerCenter - obstacleCenter).distance;
      if (distance < _playerRadius + o.size * 0.5) {
        return true;
      }
    }
    return false;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_screenSize == null) return;
    setState(() {
      _playerX = (_playerX + details.delta.dx / _screenSize!.width)
          .clamp(0.05, 0.95);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Scaffold(
          backgroundColor: Colors.black,
          body: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(seconds: 6),
            builder: (context, t, child) {
              final hue = (t * 360) % 360;
              final colors = [
                HSVColor.fromAHSV(1, hue, 0.9, 1).toColor(),
                HSVColor.fromAHSV(1, (hue + 70) % 360, 0.9, 0.9).toColor(),
                HSVColor.fromAHSV(1, (hue + 140) % 360, 0.9, 0.7).toColor(),
              ];
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.2,
                    colors: [
                      colors[0].withOpacity(0.18),
                      colors[1].withOpacity(0.16),
                      Colors.black,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    GestureDetector(
                      onPanUpdate: _handlePanUpdate,
                      onTap: () {
                        if (!_isRunning) _startGame();
                      },
                      child: CustomPaint(
                        painter: _GamePainter(
                          sparkles: _sparkles,
                          obstacles: _obstacles,
                          playerX: _playerX,
                          playerRadius: _playerRadius,
                          hue: hue,
                          isGameOver: _isGameOver,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    _buildHud(context),
                    if (!_isRunning) _buildStartOverlay(context),
                    if (_isGameOver) _buildGameOver(context),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHud(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _glass(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '스코어',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _score.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            _glass(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '최고기록',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _bestScore.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStartOverlay(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'NEON RUN',
            style: TextStyle(
              fontSize: 42,
              letterSpacing: 4,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(color: Colors.pinkAccent, blurRadius: 16),
                Shadow(color: Colors.cyanAccent, blurRadius: 24),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '드래그로 움직이고 네온 장벽을 피하세요!',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: _startGame,
            child: const Text('게임 시작'),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOver(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'GAME OVER',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.redAccent, blurRadius: 18),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '점수 ${_score.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 20, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startGame,
                icon: const Icon(Icons.refresh),
                label: const Text('다시하기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withOpacity(0.9),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter({
    required this.sparkles,
    required this.obstacles,
    required this.playerX,
    required this.playerRadius,
    required this.hue,
    required this.isGameOver,
  });

  final List<_Sparkle> sparkles;
  final List<_Obstacle> obstacles;
  final double playerX;
  final double playerRadius;
  final double hue;
  final bool isGameOver;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawSparkles(canvas, size);
    _drawPlayer(canvas, size);
    _drawObstacles(canvas, size);
    if (isGameOver) _drawFlash(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HSVColor.fromAHSV(1, hue, 0.8, 0.5).toColor().withOpacity(0.3),
          Colors.black,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawSparkles(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final color = HSVColor.fromAHSV(0.9, s.hue, 0.9, 1).toColor();
      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size + 0.6,
        paint,
      );
    }
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final center = Offset(playerX * size.width, size.height * 0.82);
    final glow = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(center, playerRadius * 1.4, glow);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.cyanAccent,
          Colors.blueAccent.shade700,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: playerRadius));
    canvas.drawCircle(center, playerRadius, paint);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(0.7);
    canvas.drawCircle(center, playerRadius * 1.15, ring);
  }

  void _drawObstacles(Canvas canvas, Size size) {
    for (final o in obstacles) {
      final center = Offset(o.x * size.width, o.y);
      final rect = Rect.fromCenter(
        center: center,
        width: o.size,
        height: o.size,
      );
      final color = HSVColor.fromAHSV(1, o.hue, 0.8, 1).toColor();

      final glow = Paint()
        ..color = color.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(14)),
        glow,
      );

      final paint = Paint()
        ..shader = LinearGradient(
          colors: [color, Colors.deepPurpleAccent.shade100],
        ).createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        paint,
      );
    }
  }

  void _drawFlash(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.redAccent.withOpacity(0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide * 0.8,
      ));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.hue,
  });

  double x;
  double y; // 0~1 normalized for convenience
  double speed; // px per second
  double size;
  double hue;
}

class _Obstacle {
  _Obstacle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.hue,
  });

  double x; // normalized
  double y; // px
  double size; // px
  double speed; // px per second
  double hue;
}

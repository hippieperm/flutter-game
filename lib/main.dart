import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
  final List<_Collectible> _collectibles = [];
  final List<_PowerUp> _powerUps = [];
  final List<double> _recentFps = [];
  final List<_LeaderboardEntry> _leaderboard = [];

  double _playerX = 0.5; // 0~1 normalized
  double _score = 0;
  double _bestScore = 0;
  int _coins = 0;
  int _combo = 0;

  bool _isRunning = false;
  bool _isGameOver = false;
  bool _fever = false;
  double _feverTimer = 0;

  double _spawnTimer = 0;
  double _collectibleTimer = 0;
  double _powerUpTimer = 0;
  static const double _playerRadius = 26;

  // Settings & accessibility
  bool _soundOn = true;
  bool _hapticsOn = true;
  bool _colorBlindMode = false;
  bool _lowFxMode = false;
  bool _showFps = false;

  // Missions
  final List<_Mission> _missions = [
    _Mission('점수 300 달성', (s, c, combo) => s >= 300),
    _Mission('코인 10개 수집', (s, c, combo) => c >= 10),
    _Mission('콤보 8 유지', (s, c, combo) => combo >= 8),
  ];

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
    for (int i = 0; i < (_lowFxMode ? 45 : 110); i++) {
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
      _collectibles.clear();
      _powerUps.clear();
      _score = 0;
      _coins = 0;
      _combo = 0;
      _spawnTimer = 0;
      _collectibleTimer = 0;
      _powerUpTimer = 0;
      _playerX = 0.5;
      _isRunning = true;
      _isGameOver = false;
      _fever = false;
      _feverTimer = 0;
      for (final m in _missions) {
        m.completed = false;
      }
    });
  }

  void _endGame() {
    setState(() {
      _isRunning = false;
      _isGameOver = true;
      _bestScore = max(_bestScore, _score);
      _leaderboard.add(
        _LeaderboardEntry(score: _score, coins: _coins, time: DateTime.now()),
      );
      _leaderboard.sort((a, b) => b.score.compareTo(a.score));
      if (_leaderboard.length > 5) _leaderboard.removeLast();
    });
  }

  void _onTick(Duration now) {
    final double dt = _lastTick == null
        ? 0
        : (now - _lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    if (!_isRunning || _screenSize == null || dt <= 0) return;

    final speedScale = _hasEffect(_PowerUpType.slow) ? 0.6 : 1.0;

    _updateFps(dt);
    _updateSparkles(dt);
    _updateObstacles(dt * speedScale);
    _updateCollectibles(dt * speedScale);
    _updatePowerUps(dt);
    _tickFever(dt);
    _score += dt * (_fever ? 22 : 10) * speedScale;

    _updateMissions();

    final bool hit = _checkCollision();
    if (hit) {
      _playHaptic();
      _playSound();
      _endGame();
      return;
    }

    setState(() {});
  }

  void _updateFps(double dt) {
    final fps = 1 / dt;
    _recentFps.add(fps);
    if (_recentFps.length > 30) _recentFps.removeAt(0);
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
    final spawnInterval = max(0.45, 1.1 - _score / 420); // faster over time

    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      _obstacles.add(_randomObstacle(size.height));
    }

    _obstacles.removeWhere((o) {
      o.y += o.speed * dt;
      if (o.type == _ObstacleType.moving) {
        o.phase += dt;
      }
      if (o.type == _ObstacleType.pulsing) {
        o.pulse += dt * 3;
      }
      return o.y - o.size > size.height;
    });
  }

  _Obstacle _randomObstacle(double screenHeight) {
    final baseSpeed = 180 + _rand.nextDouble() * 140 + _score * 0.35;
    final size = 34 + _rand.nextDouble() * 32;
    final hue = _rand.nextDouble() * 360;
    final typeRoll = _rand.nextDouble();
    if (typeRoll > 0.67) {
      return _Obstacle.moving(
        x: 0.1 + _rand.nextDouble() * 0.8,
        y: -60,
        size: size,
        speed: baseSpeed * 0.9,
        hue: hue,
        phase: _rand.nextDouble() * pi,
        amplitude: 32 + _rand.nextDouble() * 40,
      );
    } else if (typeRoll > 0.33) {
      return _Obstacle.pulsing(
        x: 0.1 + _rand.nextDouble() * 0.8,
        y: -60,
        size: size,
        speed: baseSpeed * 1.05,
        hue: hue,
      );
    } else {
      return _Obstacle.basic(
        x: 0.1 + _rand.nextDouble() * 0.8,
        y: -60,
        size: size,
        speed: baseSpeed,
        hue: hue,
      );
    }
  }

  void _updateCollectibles(double dt) {
    final size = _screenSize!;
    _collectibleTimer += dt;
    if (_collectibleTimer >= 1.4) {
      _collectibleTimer = 0;
      _collectibles.add(
        _Collectible(
          x: 0.1 + _rand.nextDouble() * 0.8,
          y: -30,
          size: 20,
          speed: 160 + _rand.nextDouble() * 80,
        ),
      );
    }

    _collectibles.removeWhere((c) {
      // Magnet effect pulls coins toward player
      if (_fever || _hasEffect(_PowerUpType.magnet)) {
        final player = Offset(_playerX * size.width, size.height * 0.82);
        final toPlayer = player - Offset(c.x * size.width, c.y);
        final dir = toPlayer / (toPlayer.distance + 0.001);
        c.x += dir.dx * dt * 1.2;
        c.y += dir.dy * dt * 1.2 * 160;
      }
      c.y += c.speed * dt;
      return c.y - c.size > size.height;
    });

    _checkCollectiblePickup();
  }

  void _updatePowerUps(double dt) {
    _powerUpTimer += dt;
    if (_powerUpTimer >= 6) {
      _powerUpTimer = 0;
      _powerUps.add(
        _PowerUp(
          x: 0.2 + _rand.nextDouble() * 0.6,
          y: -40,
          size: 26,
          speed: 150,
          kind: _randomPowerUpType(),
        ),
      );
    }

    _powerUps.removeWhere((p) {
      p.y += p.speed * dt;
      return p.y - p.size > _screenSize!.height;
    });

    for (final effect in _activeEffects) {
      effect.timeLeft -= dt;
    }
    _activeEffects.removeWhere((e) => e.timeLeft <= 0);
  }

  _PowerUpType _randomPowerUpType() {
    final roll = _rand.nextDouble();
    if (roll > 0.66) return _PowerUpType.invincible;
    if (roll > 0.33) return _PowerUpType.slow;
    return _PowerUpType.magnet;
  }

  bool _checkCollision() {
    final size = _screenSize!;
    final playerCenter = Offset(_playerX * size.width, size.height * 0.82);

    for (final o in _obstacles) {
      final obstacleCenter = Offset(o.renderX(size.width), o.y);
      final dynamicSize = o.dynamicSize();
      final distance = (playerCenter - obstacleCenter).distance;
      final collided = distance < _playerRadius + dynamicSize * 0.5;
      if (collided && !_hasEffect(_PowerUpType.invincible)) {
        return true;
      }
    }
    return false;
  }

  void _checkCollectiblePickup() {
    final size = _screenSize!;
    final playerCenter = Offset(_playerX * size.width, size.height * 0.82);

    _collectibles.removeWhere((c) {
      final coinCenter = Offset(c.x * size.width, c.y);
      final distance = (playerCenter - coinCenter).distance;
      if (distance < _playerRadius + c.size * 0.5) {
        _coins += 1;
        _combo += 1;
        _score += 15;
        _playHaptic();
        _playSound();
        _tryEnterFever();
        return true;
      }
      return false;
    });

    _powerUps.removeWhere((p) {
      final center = Offset(p.x * size.width, p.y);
      final distance = (playerCenter - center).distance;
      if (distance < _playerRadius + p.size * 0.5) {
        _activateEffect(p.kind);
        _playHaptic();
        _playSound();
        return true;
      }
      return false;
    });
  }

  void _tryEnterFever() {
    if (_combo >= 10 && !_fever) {
      _fever = true;
      _feverTimer = 6;
    }
  }

  void _tickFever(double dt) {
    if (_fever) {
      _feverTimer -= dt;
      if (_feverTimer <= 0) {
        _fever = false;
        _combo = 0;
      }
    }
  }

  final List<_ActiveEffect> _activeEffects = [];

  bool _hasEffect(_PowerUpType type) =>
      _activeEffects.any((e) => e.type == type && e.timeLeft > 0);

  void _activateEffect(_PowerUpType type) {
    double duration = 5;
    if (type == _PowerUpType.invincible) duration = 4;
    if (type == _PowerUpType.slow) duration = 4.5;
    _activeEffects.removeWhere((e) => e.type == type);
    _activeEffects.add(_ActiveEffect(type: type, timeLeft: duration));
  }

  void _updateMissions() {
    for (final m in _missions) {
      if (!m.completed && m.check(_score, _coins, _combo)) {
        m.completed = true;
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_screenSize == null) return;
    setState(() {
      _playerX = (_playerX + details.delta.dx / _screenSize!.width).clamp(
        0.05,
        0.95,
      );
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    // inertia for extra juice
    if (_screenSize == null) return;
    final vx = details.velocity.pixelsPerSecond.dx / _screenSize!.width;
    _playerX = (_playerX + vx * 0.08).clamp(0.05, 0.95);
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
              final colors = _colorBlindMode
                  ? [Colors.yellow.shade300, Colors.blue.shade300, Colors.black]
                  : [
                      HSVColor.fromAHSV(1, hue, 0.9, 1).toColor(),
                      HSVColor.fromAHSV(
                        1,
                        (hue + 70) % 360,
                        0.9,
                        0.9,
                      ).toColor(),
                      HSVColor.fromAHSV(
                        1,
                        (hue + 140) % 360,
                        0.9,
                        0.7,
                      ).toColor(),
                    ];

              _tickFever(1 / 60); // approximate per frame

              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.2,
                    colors: [
                      colors[0].withOpacity(_lowFxMode ? 0.08 : 0.18),
                      colors[1].withOpacity(_lowFxMode ? 0.06 : 0.16),
                      Colors.black,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    GestureDetector(
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      onTap: () {
                        if (!_isRunning) _startGame();
                      },
                      child: CustomPaint(
                        painter: _GamePainter(
                          sparkles: _sparkles,
                          obstacles: _obstacles,
                          collectibles: _collectibles,
                          powerUps: _powerUps,
                          playerX: _playerX,
                          playerRadius: _playerRadius,
                          hue: hue,
                          isGameOver: _isGameOver,
                          fever: _fever,
                          colorBlindMode: _colorBlindMode,
                          lowFx: _lowFxMode,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    _buildHud(context),
                    if (!_isRunning) _buildStartOverlay(context),
                    if (_isGameOver) _buildGameOver(context),
                    _buildSettingsButton(),
                    _buildMissionPanel(),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('스코어', style: _labelStyle),
                      Text(_score.toStringAsFixed(0), style: _bigNumber),
                    ],
                  ),
                ),
                _glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('최고기록', style: _labelStyle),
                      Text(
                        _bestScore.toStringAsFixed(0),
                        style: _midNumber.copyWith(color: Colors.cyanAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _glass(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.diamond, color: Colors.amber, size: 18),
                      const SizedBox(width: 6),
                      Text('$_coins', style: _midNumber),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _glass(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department,
                        color: Colors.orangeAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text('x$_combo', style: _midNumber),
                      if (_fever)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _pill('FEVER'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _glass(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _activeEffects
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _pill(_effectLabel(e.type)),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (_showFps) ...[
                  const SizedBox(width: 10),
                  _glass(
                    child: Text(
                      'FPS ${_recentFps.isEmpty ? '-' : _recentFps.reduce((a, b) => a + b) ~/ _recentFps.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ),
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
            '드래그로 움직이고 네온 장벽을 피하세요!\n코인으로 콤보를 이어 피버 모드에 진입하세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
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
                  shadows: [Shadow(color: Colors.redAccent, blurRadius: 18)],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '점수 ${_score.toStringAsFixed(0)} | 코인 $_coins | 콤보 x$_combo',
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              _glass(
                child: Column(
                  children: _leaderboard
                      .asMap()
                      .entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '#${e.key + 1}  ${e.value.score.toStringAsFixed(0)}점  (${e.value.coins}코인)',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _startGame,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withOpacity(0.9),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final summary =
                          '네온런 점수 ${_score.toStringAsFixed(0)}점, 코인 $_coins, 콤보 x$_combo!';
                      await Clipboard.setData(ClipboardData(text: summary));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('클립보드에 점수 복사됨'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('점수 공유'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsButton() {
    return Positioned(
      right: 12,
      top: 12,
      child: _glass(
        child: PopupMenuButton<String>(
          onSelected: (value) {
            setState(() {
              switch (value) {
                case 'sound':
                  _soundOn = !_soundOn;
                  break;
                case 'haptics':
                  _hapticsOn = !_hapticsOn;
                  break;
                case 'color':
                  _colorBlindMode = !_colorBlindMode;
                  break;
                case 'fx':
                  _lowFxMode = !_lowFxMode;
                  _initSparkles();
                  break;
                case 'fps':
                  _showFps = !_showFps;
                  break;
              }
            });
          },
          child: const Icon(Icons.settings, color: Colors.white),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'sound',
              child: Text('사운드 ${_soundOn ? 'ON' : 'OFF'}'),
            ),
            PopupMenuItem(
              value: 'haptics',
              child: Text('진동 ${_hapticsOn ? 'ON' : 'OFF'}'),
            ),
            PopupMenuItem(
              value: 'color',
              child: Text('색약 모드 ${_colorBlindMode ? 'ON' : 'OFF'}'),
            ),
            PopupMenuItem(
              value: 'fx',
              child: Text('저자극 모드 ${_lowFxMode ? 'ON' : 'OFF'}'),
            ),
            PopupMenuItem(
              value: 'fps',
              child: Text('FPS 표시 ${_showFps ? 'ON' : 'OFF'}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionPanel() {
    return Positioned(
      left: 12,
      bottom: 12,
      child: _glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('데일리 미션', style: _labelStyle),
            ..._missions.map(
              (m) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    m.completed ? Icons.check_circle : Icons.circle_outlined,
                    color: m.completed ? Colors.cyanAccent : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    m.title,
                    style: TextStyle(
                      color: m.completed ? Colors.white : Colors.white70,
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

  void _playSound() {
    if (_soundOn) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  void _playHaptic() {
    if (_hapticsOn) {
      HapticFeedback.lightImpact();
    }
  }

  String _effectLabel(_PowerUpType type) {
    switch (type) {
      case _PowerUpType.invincible:
        return '무적';
      case _PowerUpType.slow:
        return '슬로우';
      case _PowerUpType.magnet:
        return '자석';
    }
  }
}

const _labelStyle = TextStyle(
  color: Colors.white70,
  fontSize: 12,
  letterSpacing: 1.2,
);

const _bigNumber = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.bold,
  color: Colors.white,
);

const _midNumber = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: Colors.white,
);

class _GamePainter extends CustomPainter {
  _GamePainter({
    required this.sparkles,
    required this.obstacles,
    required this.collectibles,
    required this.powerUps,
    required this.playerX,
    required this.playerRadius,
    required this.hue,
    required this.isGameOver,
    required this.fever,
    required this.colorBlindMode,
    required this.lowFx,
  });

  final List<_Sparkle> sparkles;
  final List<_Obstacle> obstacles;
  final List<_Collectible> collectibles;
  final List<_PowerUp> powerUps;
  final double playerX;
  final double playerRadius;
  final double hue;
  final bool isGameOver;
  final bool fever;
  final bool colorBlindMode;
  final bool lowFx;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawSparkles(canvas, size);
    _drawPlayer(canvas, size);
    _drawObstacles(canvas, size);
    _drawCollectibles(canvas, size);
    _drawPowerUps(canvas, size);
    if (isGameOver) _drawFlash(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colorBlindMode
            ? [Colors.yellow.shade200.withOpacity(0.25), Colors.black]
            : [
                HSVColor.fromAHSV(1, hue, 0.8, 0.5).toColor().withOpacity(0.3),
                Colors.black,
              ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawSparkles(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final color = colorBlindMode
          ? Colors.white70
          : HSVColor.fromAHSV(0.9, s.hue, 0.9, 1).toColor();
      final paint = Paint()
        ..color = color.withOpacity(lowFx ? 0.35 : 0.6)
        ..maskFilter = lowFx
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size + 0.6,
        paint,
      );
    }
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final center = Offset(playerX * size.width, size.height * 0.82);
    if (!lowFx) {
      final glow = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
      canvas.drawCircle(center, playerRadius * 1.4, glow);
    }

    final paint = Paint()
      ..shader = RadialGradient(
        colors: fever
            ? [Colors.amber, Colors.orangeAccent, Colors.redAccent]
            : [Colors.white, Colors.cyanAccent, Colors.blueAccent.shade700],
      ).createShader(Rect.fromCircle(center: center, radius: playerRadius));
    canvas.drawCircle(center, playerRadius, paint);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = (fever ? Colors.orangeAccent : Colors.white).withOpacity(0.7);
    canvas.drawCircle(center, playerRadius * 1.15, ring);
  }

  void _drawObstacles(Canvas canvas, Size size) {
    for (final o in obstacles) {
      final center = Offset(o.renderX(size.width), o.y);
      final dynamicSize = o.dynamicSize();
      final rect = Rect.fromCenter(
        center: center,
        width: dynamicSize,
        height: dynamicSize,
      );
      final color = colorBlindMode
          ? Colors.deepOrangeAccent
          : HSVColor.fromAHSV(1, o.hue, 0.8, 1).toColor();

      if (!lowFx) {
        final glow = Paint()
          ..color = color.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(14)),
          glow,
        );
      }

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

  void _drawCollectibles(Canvas canvas, Size size) {
    for (final c in collectibles) {
      final center = Offset(c.x * size.width, c.y);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.amber, Colors.deepOrange],
        ).createShader(Rect.fromCircle(center: center, radius: c.size));
      if (!lowFx) {
        final glow = Paint()
          ..color = Colors.amber.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
        canvas.drawCircle(center, c.size * 0.9, glow);
      }
      canvas.drawCircle(center, c.size * 0.8, paint);
    }
  }

  void _drawPowerUps(Canvas canvas, Size size) {
    for (final p in powerUps) {
      final center = Offset(p.x * size.width, p.y);
      final color = _powerUpColor(p.kind);
      final paint = Paint()
        ..shader = SweepGradient(
          colors: [Colors.white, color],
        ).createShader(Rect.fromCircle(center: center, radius: p.size));
      if (!lowFx) {
        canvas.drawCircle(
          center,
          p.size * 1.2,
          Paint()
            ..color = color.withOpacity(0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
      canvas.drawCircle(center, p.size * 0.9, paint);
    }
  }

  Color _powerUpColor(_PowerUpType type) {
    switch (type) {
      case _PowerUpType.invincible:
        return Colors.greenAccent;
      case _PowerUpType.slow:
        return Colors.blueAccent;
      case _PowerUpType.magnet:
        return Colors.pinkAccent;
    }
  }

  void _drawFlash(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.redAccent.withOpacity(lowFx ? 0.2 : 0.35),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: size.center(Offset.zero),
              radius: size.shortestSide * 0.8,
            ),
          );
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

enum _ObstacleType { basic, moving, pulsing }

class _Obstacle {
  _Obstacle.basic({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.hue,
  }) : type = _ObstacleType.basic;

  _Obstacle.moving({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.hue,
    required this.phase,
    required this.amplitude,
  }) : type = _ObstacleType.moving,
       pulse = 0;

  _Obstacle.pulsing({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.hue,
  }) : type = _ObstacleType.pulsing,
       phase = 0,
       amplitude = 0,
       pulse = 0;

  final _ObstacleType type;
  double x; // normalized
  double y; // px
  double size; // px
  double speed; // px per second
  double hue;
  double phase = 0;
  double amplitude = 0;
  double pulse = 0;

  double renderX(double width) {
    if (type == _ObstacleType.moving) {
      return (x * width + sin(phase * 2) * amplitude).clamp(40, width - 40);
    }
    return x * width;
  }

  double dynamicSize() {
    if (type == _ObstacleType.pulsing) {
      return size * (1 + sin(pulse) * 0.2);
    }
    return size;
  }
}

class _Collectible {
  _Collectible({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
  });

  double x; // normalized
  double y; // px
  double size;
  double speed;
}

enum _PowerUpType { invincible, slow, magnet }

class _PowerUp {
  _PowerUp({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.kind,
  });

  double x; // normalized
  double y; // px
  double size; // px
  double speed; // px per second
  final _PowerUpType kind;
}

class _ActiveEffect {
  _ActiveEffect({required this.type, required this.timeLeft});

  final _PowerUpType type;
  double timeLeft;
}

class _Mission {
  _Mission(this.title, this.checker);

  final String title;
  final bool Function(double score, int coins, int combo) checker;
  bool completed = false;

  bool check(double score, int coins, int combo) =>
      checker(score, coins, combo);
}

class _LeaderboardEntry {
  _LeaderboardEntry({
    required this.score,
    required this.coins,
    required this.time,
  });
  final double score;
  final int coins;
  final DateTime time;
}

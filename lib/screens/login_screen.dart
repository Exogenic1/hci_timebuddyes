import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/auth_service.dart';
import 'dart:math' as math;
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _showClock = false;
  bool _obscurePassword = true; // Controls password visibility
  bool _showEmailError = false; // Controls email error visibility
  bool _showPasswordError = false; // Controls password error visibility

  void _toggleClock() {
    setState(() {
      _showClock = !_showClock;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        automaticallyImplyLeading: false,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _toggleClock,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (widget, animation) =>
                      ScaleTransition(scale: animation, child: widget),
                  child: _showClock
                      ? const AnalogClockWidget(key: ValueKey('clock'))
                      : Image.asset(
                          'assets/login_image.png',
                          key: const ValueKey('image'),
                          height: 315,
                          width: 315,
                        ),
                ),
              ),
              const SizedBox(height: 32),
              _buildEmailTextField(),
              const SizedBox(height: 16),
              _buildPasswordTextField(),
              const SizedBox(height: 32),
              _buildSignInButton(authService),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              _buildGoogleSignInButton(authService),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/signup');
                },
                child: const Text(
                  "Don't have an account? Sign up",
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailTextField() {
    return TextField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'Email',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.email),
        filled: true,
        fillColor: Colors.white,
        errorText: _showEmailError ? 'Email is required' : null,
      ),
      onChanged: (value) {
        setState(() {
          _showEmailError = false; // Hide error when user starts typing
        });
      },
    );
  }

  Widget _buildPasswordTextField() {
    return TextField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Password',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon:
              Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () {
            setState(() {
              _obscurePassword =
                  !_obscurePassword; // Toggle password visibility
            });
          },
        ),
        filled: true,
        fillColor: Colors.white,
        errorText: _showPasswordError ? 'Password is required' : null,
      ),
      obscureText: _obscurePassword,
      onChanged: (value) {
        setState(() {
          _showPasswordError = false; // Hide error when user starts typing
        });
      },
    );
  }

  Widget _buildSignInButton(AuthService authService) {
    return ElevatedButton(
      onPressed: () async {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        // Validate fields
        setState(() {
          _showEmailError = email.isEmpty;
          _showPasswordError = password.isEmpty;
        });

        if (email.isEmpty || password.isEmpty) {
          return; // Stop if any field is empty
        }

        // Sign in with email and password
        final user = await authService.signInWithEmail(email, password);
        if (user != null) {
          // Navigate to the home screen
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login failed. Please check your credentials.'),
            ),
          );
        }
      },
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.blue),
      child: const Text(
        'Sign in with Email',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }

  Widget _buildGoogleSignInButton(AuthService authService) {
    return ElevatedButton(
      onPressed: () async {
        await authService.signInWithGoogle(context);
      },
      style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: const Color.fromARGB(255, 214, 193, 162)),
      child: const Text(
        'Sign in with Google',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}

class AnalogClockWidget extends StatefulWidget {
  const AnalogClockWidget({super.key});

  @override
  State<AnalogClockWidget> createState() => _AnalogClockWidgetState();
}

class _AnalogClockWidgetState extends State<AnalogClockWidget> {
  late Timer _timer;
  DateTime _dateTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _dateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(315, 315),
      painter: AnalogClockPainter(_dateTime),
    );
  }
}

class AnalogClockPainter extends CustomPainter {
  final DateTime dateTime;

  AnalogClockPainter(this.dateTime);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final center = Offset(centerX, centerY);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, borderPaint);

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    final textStyle = TextStyle(color: Colors.black, fontSize: 20);

    for (int i = 1; i <= 12; i++) {
      final angle = (i * 30) * (math.pi / 180);
      final x = centerX + (radius - 25) * math.cos(angle - math.pi / 2);
      final y = centerY + (radius - 25) * math.sin(angle - math.pi / 2);
      textPainter.text = TextSpan(text: '$i', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas,
          Offset(x - textPainter.width / 2, y - textPainter.height / 2));
    }

    final hourHandPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6;
    final hourAngle =
        (dateTime.hour % 12 + dateTime.minute / 60) * 30 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.5 * math.cos(hourAngle - math.pi / 2),
            centerY + radius * 0.5 * math.sin(hourAngle - math.pi / 2)),
        hourHandPaint);

    final minuteHandPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4;
    final minuteAngle = dateTime.minute * 6 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.7 * math.cos(minuteAngle - math.pi / 2),
            centerY + radius * 0.7 * math.sin(minuteAngle - math.pi / 2)),
        minuteHandPaint);

    final secondHandPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    final secondAngle = dateTime.second * 6 * (math.pi / 180);
    canvas.drawLine(
        center,
        Offset(centerX + radius * 0.8 * math.cos(secondAngle - math.pi / 2),
            centerY + radius * 0.8 * math.sin(secondAngle - math.pi / 2)),
        secondHandPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

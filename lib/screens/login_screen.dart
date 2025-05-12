import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/screens/home.dart';
import 'package:time_buddies/services/auth_service.dart';
import 'package:time_buddies/widgets/analog_clock_widget.dart'; // Import the separate clock widget

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
  bool _isLoading = false; // Track loading state

  void _toggleClock() {
    setState(() {
      _showClock = !_showClock;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    // Get available height to adjust UI based on keyboard visibility
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isKeyboardVisible = viewInsets.bottom > 0;

    // Calculate appropriate image/clock size based on keyboard visibility
    final imageSize =
        isKeyboardVisible ? 80.0 : 180.0; // Restored to original size of 180.0

    return Scaffold(
      // Set resizeToAvoidBottomInset to true to ensure the screen resizes when the keyboard appears
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'Login',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Wrap the main content in a SafeArea to respect system UI like the status bar
          SafeArea(
            child: GestureDetector(
              // Add this to dismiss keyboard when tapping outside of text fields
              onTap: () => FocusScope.of(context).unfocus(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                // Use a ListView instead of a Column to make the content scrollable
                child: ListView(
                  physics:
                      const ClampingScrollPhysics(), // Smoother scrolling behavior
                  children: [
                    // Add some top padding for better visual balance
                    const SizedBox(height: 12),
                    // Logo/Clock section - reduce or hide when keyboard is visible
                    Container(
                      height: isKeyboardVisible
                          ? 100
                          : 180, // Restored to original height
                      child: Center(
                        child: GestureDetector(
                          onTap: _toggleClock,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            transitionBuilder: (widget, animation) =>
                                ScaleTransition(
                                    scale: animation, child: widget),
                            child: _showClock
                                ? AnalogClockWidget(
                                    key: const ValueKey('clock'),
                                    size: imageSize,
                                  )
                                : Image.asset(
                                    'assets/login_image.png',
                                    key: const ValueKey('image'),
                                    height: imageSize,
                                    width: imageSize,
                                  ),
                          ),
                        ),
                      ),
                    ),

                    // Add some space between the clock/image and the form
                    const SizedBox(height: 28), // Increased spacing

                    // Form section
                    const SizedBox(height: 24), // Increased spacing
                    _buildEmailTextField(),
                    const SizedBox(height: 20), // Increased spacing
                    _buildPasswordTextField(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/forgot_password');
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    _buildSignInButton(authService),
                    const SizedBox(height: 24), // Increased spacing
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            'OR',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    _buildGoogleSignInButton(authService),
                    const SizedBox(height: 20), // Increased spacing

                    // Bottom section
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.pushReplacementNamed(
                                  context, '/signup');
                            },
                      child: const Text(
                        "Don't have an account? Sign up",
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),

                    // Extra space at bottom to ensure scrollability
                    SizedBox(height: isKeyboardVisible ? 200 : 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTextField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _showEmailError
                ? Colors.red.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _emailController,
        decoration: InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _showEmailError ? Colors.red : Colors.grey,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Colors.blue,
              width: 2,
            ),
          ),
          prefixIcon: const Icon(Icons.email),
          filled: true,
          fillColor: Colors.white,
          errorText: _showEmailError ? 'Email is required' : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onChanged: (value) {
          setState(() {
            _showEmailError = false; // Hide error when user starts typing
          });
        },
        enabled: !_isLoading,
        keyboardType:
            TextInputType.emailAddress, // Set appropriate keyboard type
      ),
    );
  }

  Widget _buildPasswordTextField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _showPasswordError
                ? Colors.red.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _passwordController,
        decoration: InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _showPasswordError ? Colors.red : Colors.grey,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Colors.blue,
              width: 2,
            ),
          ),
          prefixIcon: const Icon(Icons.lock),
          suffixIcon: IconButton(
            icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        obscureText: _obscurePassword,
        onChanged: (value) {
          setState(() {
            _showPasswordError = false; // Hide error when user starts typing
          });
        },
        enabled: !_isLoading,
        // Add text input action to help with keyboard navigation
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          // Dismiss keyboard when done
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  Widget _buildSignInButton(AuthService authService) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () async {
                // Dismiss keyboard first
                FocusScope.of(context).unfocus();

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

                // Show loading indicator
                setState(() {
                  _isLoading = true;
                });

                // Sign in with email and password
                try {
                  final user = await authService.signInWithEmail(
                      context, email, password);
                  if (user != null) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const HomeScreen()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Login failed. Please check your credentials.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Sign in',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildGoogleSignInButton(AuthService authService) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () async {
                // Dismiss keyboard first
                FocusScope.of(context).unfocus();

                setState(() {
                  _isLoading = true;
                });
                try {
                  await authService.signInWithGoogle(context);
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/google_logo.png',
              height: 24,
              width: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              'Sign in with Google',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

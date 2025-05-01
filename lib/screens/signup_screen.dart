import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_buddies/services/auth_service.dart';
import 'package:time_buddies/services/database_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _showEmailError = false;
  bool _showPasswordError = false;
  bool _showConfirmPasswordError = false;
  bool _showNameError = false;
  bool _isLoading = false; // Added loading state tracking

  // Function to check password strength
  String _checkPasswordStrength(String password) {
    if (password.isEmpty) return '';
    if (password.length < 6) return 'Weak';
    if (password.length < 8) return 'Medium';
    if (!RegExp(r'[A-Z]').hasMatch(password)) return 'Medium';
    if (!RegExp(r'[0-9]').hasMatch(password)) return 'Medium';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) return 'Medium';
    return 'Strong';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final databaseService = Provider.of<DatabaseService>(context);

    // Get keyboard visibility state
    final viewInsets = MediaQuery.of(context).viewInsets;
    final isKeyboardVisible = viewInsets.bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sign Up',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            child: GestureDetector(
              // Dismiss keyboard when tapping outside text fields
              onTap: () => FocusScope.of(context).unfocus(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  children: [
                    // Add some top padding
                    const SizedBox(height: 12),

                    // Add spacing
                    const SizedBox(height: 28),

                    // Form section
                    const SizedBox(height: 24),
                    _buildNameTextField(),
                    const SizedBox(height: 20),
                    _buildEmailTextField(),
                    const SizedBox(height: 20),
                    _buildPasswordTextField(),
                    const SizedBox(height: 8),
                    _buildPasswordStrengthIndicator(),
                    const SizedBox(height: 20),
                    _buildConfirmPasswordTextField(),
                    const SizedBox(height: 32),
                    _buildSignUpButton(authService, databaseService),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 24),
                    _buildGoogleSignUpButton(authService),
                    const SizedBox(height: 20),

                    // Bottom section
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.pushReplacementNamed(context, '/login');
                            },
                      child: const Text(
                        'Already have an account? Login',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),

                    // Extra space at bottom
                    SizedBox(height: isKeyboardVisible ? 200 : 20),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNameTextField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _showNameError
                ? Colors.red.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _showNameError ? Colors.red : Colors.grey,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Colors.blue,
              width: 2,
            ),
          ),
          prefixIcon: const Icon(Icons.person),
          filled: true,
          fillColor: Colors.white,
          errorText: _showNameError ? 'Name is required' : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onChanged: (value) {
          setState(() {
            _showNameError = false;
          });
        },
        enabled: !_isLoading,
        textInputAction: TextInputAction.next,
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
            _showEmailError = false;
          });
        },
        enabled: !_isLoading,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
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
                _obscurePassword = !_obscurePassword;
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
            _showPasswordError = false;
          });
        },
        enabled: !_isLoading,
        textInputAction: TextInputAction.next,
      ),
    );
  }

  Widget _buildConfirmPasswordTextField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _showConfirmPasswordError
                ? Colors.red.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _confirmPasswordController,
        decoration: InputDecoration(
          labelText: 'Confirm Password',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _showConfirmPasswordError ? Colors.red : Colors.grey,
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
            icon: Icon(_obscureConfirmPassword
                ? Icons.visibility
                : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
          ),
          filled: true,
          fillColor: Colors.white,
          errorText:
              _showConfirmPasswordError ? 'Confirm Password is required' : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        obscureText: _obscureConfirmPassword,
        onChanged: (value) {
          setState(() {
            _showConfirmPasswordError = false;
          });
        },
        enabled: !_isLoading,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          // Dismiss keyboard when done
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  Widget _buildPasswordStrengthIndicator() {
    final strength = _checkPasswordStrength(_passwordController.text);
    Color strengthColor = Colors.grey;
    if (strength == 'Weak') strengthColor = Colors.red;
    if (strength == 'Medium') strengthColor = Colors.orange;
    if (strength == 'Strong') strengthColor = Colors.green;

    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: strength == 'Weak'
                ? 0.33
                : strength == 'Medium'
                    ? 0.66
                    : strength == 'Strong'
                        ? 1.0
                        : 0.0,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          strength,
          style: TextStyle(color: strengthColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(
      AuthService authService, DatabaseService databaseService) {
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
                final confirmPassword = _confirmPasswordController.text.trim();
                final name = _nameController.text.trim();

                // Validate fields
                setState(() {
                  _showEmailError = email.isEmpty;
                  _showPasswordError = password.isEmpty;
                  _showConfirmPasswordError = confirmPassword.isEmpty;
                  _showNameError = name.isEmpty;
                });

                if (email.isEmpty ||
                    password.isEmpty ||
                    confirmPassword.isEmpty ||
                    name.isEmpty) {
                  return; // Stop if any field is empty
                }

                if (password != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Passwords do not match.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Show loading indicator
                setState(() {
                  _isLoading = true;
                });

                try {
                  // Sign up with email and password
                  final user = await authService.signUpWithEmail(
                      context, email, password, name);
                  if (user != null) {
                    // Navigate to the home screen
                    Navigator.pushReplacementNamed(context, '/home');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sign up failed. Please try again.'),
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
        child: const Text(
          'Sign up with Email',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignUpButton(AuthService authService) {
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

                // Set loading state once at the screen level
                setState(() {
                  _isLoading = true;
                });

                // The main loading overlay will handle the visual indicator
                await authService.signInWithGoogle(context);

                // If we reach here, the navigation might have happened already
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
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
              'Sign up with Google',
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

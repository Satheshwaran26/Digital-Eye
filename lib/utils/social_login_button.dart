import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget iconWidget;
  final double size;

  const _SocialLoginButton({
    required this.onPressed,
    required this.iconWidget,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[800]!),
            borderRadius: BorderRadius.circular(30),
            color: Colors.grey[900],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(child: iconWidget),
        ),
      ),
    );
  }
}
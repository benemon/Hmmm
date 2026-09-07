import 'package:flutter/material.dart';

void showValidationError(BuildContext context, ArgumentError error) {
  showMessage(context, error.message.toString());
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

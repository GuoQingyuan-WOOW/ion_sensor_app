import 'package:flutter/material.dart';

class IonModel {
  final String ion;
  final int wavelengthNm;
  final String food;
  final Color c1;
  final Color c2;
  final IconData icon;

  const IonModel({
    required this.ion,
    required this.wavelengthNm,
    required this.food,
    required this.c1,
    required this.c2,
    required this.icon,
  });
}
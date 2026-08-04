import 'package:flutter/material.dart';

IconData nimbusRouteAccessIcon({required bool requiresConnection}) {
  return requiresConnection ? Icons.rocket_launch_rounded : Icons.language_rounded;
}

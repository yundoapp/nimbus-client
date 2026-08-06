import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/nimbus/auth/data/nimbus_auth_repository.dart';

void main() {
  test('recognizes only the legacy API rejection for the source fingerprint field', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
        statusCode: 400,
        data: {
          'code': 'VALIDATION_FAILED',
          'fields': ['publicRulesSourceVersion'],
        },
      ),
    );

    expect(isNimbusUnsupportedPublicRulesSourceVersionError(error), isTrue);
  });

  test('does not hide unrelated validation failures behind the compatibility retry', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
        statusCode: 400,
        data: {
          'code': 'VALIDATION_FAILED',
          'fields': ['appVersion'],
        },
      ),
    );

    expect(isNimbusUnsupportedPublicRulesSourceVersionError(error), isFalse);
  });

  test('recognizes Nest default validation response from an older API', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
        statusCode: 400,
        data: {
          'message': ['property publicRulesSourceVersion should not exist'],
          'error': 'Bad Request',
          'statusCode': 400,
        },
      ),
    );

    expect(isNimbusUnsupportedPublicRulesSourceVersionError(error), isTrue);
  });

  test('does not match an unrelated Nest validation message', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
        statusCode: 400,
        data: {
          'message': ['property appVersion should not exist'],
          'error': 'Bad Request',
          'statusCode': 400,
        },
      ),
    );

    expect(isNimbusUnsupportedPublicRulesSourceVersionError(error), isFalse);
  });

  test('retries a gateway-stripped 400 only when the source field was sent', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/v1/connect/plan'),
      response: Response(requestOptions: RequestOptions(path: '/api/v1/connect/plan'), statusCode: 400),
    );

    expect(shouldRetryNimbusRulesSourceCompatibility(error: error, sourceVersionWasSent: true), isTrue);
    expect(shouldRetryNimbusRulesSourceCompatibility(error: error, sourceVersionWasSent: false), isFalse);
  });
}

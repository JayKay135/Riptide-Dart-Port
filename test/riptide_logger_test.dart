import 'package:riptide/src/utils/riptide_logger.dart';
import 'package:test/test.dart';

void main() {
  group('RiptideLogger', () {
    tearDown(() => RiptideLogger.initializeExtended(null, null, null, null, false));

    test('formats messages with log names and timestamps', () {
      List<String> logs = [];
      RiptideLogger.initialize(logs.add, false);
      RiptideLogger.logWithLogName(LogType.info, 'SERVER', 'Started');
      expect(logs, equals(['(SERVER): Started']));

      RiptideLogger.initialize(logs.add, true, timestampFormat: 'HH');
      RiptideLogger.logWithLogName(LogType.info, 'SERVER', 'Started');
      expect(logs.last, matches(RegExp(r'^\[\d\d\] \(SERVER\): Started$')));
    });

    test('logs exceptions as errors if there is no exception method', () {
      List<String> errors = [];
      RiptideLogger.initializeExtended(null, null, null, errors.add, false);
      expect(RiptideLogger.isExceptionLoggingEnabled, isFalse);

      RiptideLogger.logEventException('CLIENT', 'connected', StateError('oops'), StackTrace.fromString('trace'));
      expect(errors, hasLength(1));
      expect(errors.first, startsWith("(CLIENT): An exception was thrown by a subscriber of the 'connected' event!\n"));
      expect(errors.first, contains('oops'));
      expect(errors.first, endsWith('trace'));
    });

    test('passes exceptions to the exception method', () {
      List<String> errors = [];
      List<Object> exceptions = [];
      RiptideLogger.initializeExtended(null, null, null, errors.add, false,
          exceptionMethod: (exception, stackTrace) => exceptions.add(exception));
      expect(RiptideLogger.isExceptionLoggingEnabled, isTrue);

      StateError error = StateError('oops');
      RiptideLogger.logException('SERVER', 'Something failed.', error);
      expect(errors, equals(['(SERVER): Something failed. See the following log for the exception itself.']));
      expect(exceptions, equals([error]));
    });

    test('can log without being initialized', () {
      List<String> logs = [];
      RiptideLogger.initializeExtended(null, null, null, null, false);
      RiptideLogger.enableLoggingFor(LogType.warning, logs.add);
      RiptideLogger.logWithLogName(LogType.warning, 'PEER', 'Careful');
      expect(logs, equals(['(PEER): Careful']));
    });
  });
}

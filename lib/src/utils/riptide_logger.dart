import 'package:intl/intl.dart';

// NOTE: Checked

/// Defines log message types.
enum LogType {
  /// Logs that are used for investigation during development.
  debug,

  /// Logs that provide general information about application flow.
  info,

  /// Logs that highlight abnormal or unexpected events in the application flow.
  warning,

  /// Logs that highlight problematic events in the application flow which will cause unexpected behavior if not planned for.
  error
}

/// Encapsulates a method used to log messages.
///
/// [log] : The message to log.
typedef LogMethod<String> = void Function(String log);

/// Provides functionality for logging messages.
class RiptideLogger {
  /// Whether or not LogType.debug messages will be logged.
  static bool get isDebugLoggingEnabled => logMethods.containsKey(LogType.debug);

  /// Whether or not LogType.info messages will be logged.
  static bool get isInfoLoggingEnabled => logMethods.containsKey(LogType.info);

  /// Whether or not LogType.warning messages will be logged.
  static bool get isWarningLoggingEnabled => logMethods.containsKey(LogType.warning);

  /// Whether or not LogType.error messages will be logged.
  static bool get isErrorLoggingEnabled => logMethods.containsKey(LogType.error);

  /// Log methods, accessible by their LogType
  static Map<LogType, LogMethod> _logMethods = <LogType, LogMethod>{};
  static Map<LogType, LogMethod> get logMethods => _logMethods;

  /// Whether or not to include timestamps when logging messages.
  static late bool includeTimestamps;

  /// The format to use for timestamps.
  static late String timestampFormat;

  /// Initializes RiptideLogger with all log types enabled.
  ///
  /// [logMethod] : The method to use when logging all types of messages.
  /// [includeTimestamps] : Whether or not to include timestamps when logging messages.
  /// [timestampFormat] : The format to use for timestamps.
  static void initialize(LogMethod logMethod, bool includeTimestamps, {String timestampFormat = "HH:mm:ss"}) {
    initializeExtended(logMethod, logMethod, logMethod, logMethod, includeTimestamps, timestampFormat: timestampFormat);
  }

  /// Initializes RiptideLogger with the supplied log methods.
  ///
  /// [debugMethod] : The method to use when logging debug messages. Set to null to disable debug logs.
  /// [infoMethod] : The method to use when logging info messages. Set to null to disable info logs.
  /// [warningMethod] : The method to use when logging warning messages. Set to null to disable warning logs.
  /// [errorMethod] : The method to use when logging error messages. Set to null to disable error logs.
  /// [includeTimestamps] : Whether or not to include timestamps when logging messages.
  /// [timestampFormat] : The format to use for timestamps.
  static void initializeExtended(LogMethod? debugMethod, LogMethod? infoMethod, LogMethod? warningMethod, LogMethod? errorMethod, bool includeTimestamps,
      {String timestampFormat = "HH:mm:ss"}) {
    logMethods.clear();

    if (debugMethod != null) {
      logMethods[LogType.debug] = debugMethod;
    }
    if (infoMethod != null) {
      logMethods[LogType.info] = infoMethod;
    }
    if (warningMethod != null) {
      logMethods[LogType.warning] = warningMethod;
    }
    if (errorMethod != null) {
      logMethods[LogType.error] = errorMethod;
    }

    RiptideLogger.includeTimestamps = includeTimestamps;
    RiptideLogger.timestampFormat = timestampFormat;
  }

  /// Enables logging for messages of the given LogType.
  ///
  /// [logType] : The type of message to enable logging for.
  /// [logMethod] : The method to use when logging this type of message.
  static void enableLoggingFor(LogType logType, LogMethod logMethod) {
    if (logMethods.containsKey(logType)) {
      logMethods[logType] = logMethod;
    } else {
      logMethods[logType] = logMethod;
    }
  }

  /// Disables logging for messages of the given LogType.
  ///
  /// [logType] : The type of message to enable logging for.
  static void disableLoggingFor(LogType logType) => logMethods.remove(logType);

  /// Logs a message.
  ///
  /// [logType] : The type of log message that is being logged.
  /// [message] : The message to log.
  static void log(LogType logType, String message) {
    if (logMethods.containsKey(logType)) {
      LogMethod logMethod = logMethods[logType]!;

      if (includeTimestamps) {
        logMethod("[${_getTimestamp(DateTime.now())}]: $message");
      } else {
        logMethod(message);
      }
    }
  }

  /// Logs a message.
  ///
  /// [logType] : The type of log message that is being logged.
  /// [logName] : Who is logging this message.
  /// [message] : The message to log.
  static void logWithLogName(LogType logType, String logName, String message) {
    if (logMethods.containsKey(logType)) {
      LogMethod logMethod = logMethods[logType]!;

      if (includeTimestamps) {
        logMethod("[${_getTimestamp(DateTime.now())}] ($logName): $message");
      } else {
        logMethod("($logName): $message");
      }
    }
  }

  /// Converts a DateTime object to a formatted timestamp string.
  ///
  /// [time] : The time to format.
  ///
  /// Returns the formatted timestamp.
  static String _getTimestamp(DateTime time) {
    return DateFormat(timestampFormat).format(time);
  }
}

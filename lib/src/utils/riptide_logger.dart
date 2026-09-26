import 'package:intl/intl.dart';

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

/// Encapsulates a method used to log exceptions.
///
/// [exception] : The exception to log.
/// [stackTrace] : The stack trace of the exception, if available.
///
/// This takes nothing but the exception (and its stack trace, which Dart doesn't store in exceptions) so that methods
/// which log exceptions natively can be used directly. Any accompanying message is logged separately, just before it.
typedef ExceptionLogMethod = void Function(Object exception, StackTrace? stackTrace);

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

  /// Whether or not exceptions will be passed to a dedicated log method.
  static bool get isExceptionLoggingEnabled => _exceptionLogMethod != null;

  /// Log methods, accessible by their LogType
  static final Map<LogType, LogMethod<String>> _logMethods = <LogType, LogMethod<String>>{};
  static Map<LogType, LogMethod<String>> get logMethods => _logMethods;

  /// The method to use when logging exceptions, or null to log them as LogType.error.
  static ExceptionLogMethod? _exceptionLogMethod;

  /// Whether or not to include timestamps when logging messages.
  static bool includeTimestamps = false;

  /// The format to use for timestamps.
  static String timestampFormat = "HH:mm:ss";

  /// Initializes RiptideLogger with all log types enabled.
  ///
  /// [logMethod] : The method to use when logging all types of messages.
  /// [includeTimestamps] : Whether or not to include timestamps when logging messages.
  /// [timestampFormat] : The format to use for timestamps.
  static void initialize(LogMethod<String> logMethod, bool includeTimestamps, {String timestampFormat = "HH:mm:ss"}) {
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
  /// [exceptionMethod] : The method to use when logging exceptions. Set to null to use [errorMethod] instead.
  ///
  /// Supplying an [exceptionMethod] is worthwhile for loggers which accept exceptions directly, as they can display the
  /// stack trace leading back to the code that threw.
  static void initializeExtended(LogMethod<String>? debugMethod, LogMethod<String>? infoMethod,
      LogMethod<String>? warningMethod, LogMethod<String>? errorMethod, bool includeTimestamps,
      {String timestampFormat = "HH:mm:ss", ExceptionLogMethod? exceptionMethod}) {
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

    _exceptionLogMethod = exceptionMethod;
    RiptideLogger.includeTimestamps = includeTimestamps;
    RiptideLogger.timestampFormat = timestampFormat;
  }

  /// Enables logging for messages of the given LogType.
  ///
  /// [logType] : The type of message to enable logging for.
  /// [logMethod] : The method to use when logging this type of message.
  static void enableLoggingFor(LogType logType, LogMethod<String> logMethod) {
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
      LogMethod<String> logMethod = logMethods[logType]!;

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
      logMethods[logType]!(_formatLog(logName, message));
    }
  }

  /// Logs a message along with the exception which caused it.
  ///
  /// [logName] : Who is logging this message.
  /// [message] : The message to log.
  /// [exception] : The exception which caused the message to be logged.
  /// [stackTrace] : The stack trace of the exception, if available.
  ///
  /// Exceptions are always logged as LogType.error messages. If an exception method was supplied when initializing,
  /// the exception is given to it in a log of its own, immediately after the one containing the message. Otherwise the
  /// exception is converted to text and included in the message's log.
  ///
  /// NOTE: This is an overload of Log in C#.
  static void logException(String logName, String message, Object exception, [StackTrace? stackTrace]) {
    LogMethod<String>? errorMethod = logMethods[LogType.error];

    if (_exceptionLogMethod == null) {
      errorMethod?.call(_formatLog(logName, "$message\n$exception${stackTrace == null ? "" : "\n$stackTrace"}"));
      return;
    }

    errorMethod?.call(_formatLog(logName, "$message See the following log for the exception itself."));
    _exceptionLogMethod!(exception, stackTrace);
  }

  /// Logs an exception which was thrown by a subscriber of the event with the given name.
  ///
  /// [logName] : Who is logging this message.
  /// [eventName] : The name of the event whose subscriber threw the exception.
  /// [exception] : The exception that was thrown.
  /// [stackTrace] : The stack trace of the exception, if available.
  ///
  /// Riptide catches these exceptions instead of letting them propagate, as one escaping would skip the rest of the
  /// handling of whatever triggered the event and leave the peer or connection in an inconsistent state.
  static void logEventException(String logName, String eventName, Object exception, [StackTrace? stackTrace]) {
    logException(logName, "An exception was thrown by a subscriber of the '$eventName' event!", exception, stackTrace);
  }

  /// Adds a log name, and a timestamp if they're enabled, to the given message.
  ///
  /// [logName] : Who is logging the message.
  /// [message] : The message being logged.
  ///
  /// Returns the formatted message.
  static String _formatLog(String logName, String message) {
    return includeTimestamps ? "[${_getTimestamp(DateTime.now())}] ($logName): $message" : "($logName): $message";
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

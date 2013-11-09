`(typeof window === 'undefined' ? {} : window)['chronology'] = (function(module, require){"use strict"; var exports = module.exports`

WallTime = require('walltime-js', "WallTime")

exports.isTimezone = isTimezone = (tz) ->
  return typeof tz is 'string' and tz.indexOf('/') isnt -1

exports.milliseconds = {
  floor: (dt, tz) ->
    return new Date(dt)

  ceil: (dt, tz) ->
    return new Date(dt)

  move: (dt, tz, step) ->
    return new Date(dt.valueOf() + step)
}

exports.second = {
  floor: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Seconds do not actually need a timezone because all timezones align on seconds... for now...
    dt = new Date(dt)
    dt.setUTCMilliseconds(0)
    return dt

  ceil: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Seconds do not actually need a timezone because all timezones align on seconds... for now...
    dt = new Date(dt)
    if dt.getUTCMilliseconds()
      dt.setUTCMilliseconds(1000)
    return dt

  move: (dt, tz, step) ->
    dt = new Date(dt)
    dt.setUTCSeconds(dt.getUTCSeconds() + step)
    return dt
}

exports.minute = {
  floor: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Minutes do not actually need a timezone because all timezones align on minutes... for now...
    dt = new Date(dt)
    dt.setUTCSeconds(0, 0)
    return dt

  ceil: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Minutes do not actually need a timezone because all timezones align on minutes... for now...
    dt = new Date(dt)
    if dt.getUTCMilliseconds() or dt.getUTCSeconds()
      dt.setUTCSeconds(60, 0)
    return dt

  move: (dt, tz, step) ->
    dt = new Date(dt)
    dt.setUTCMinutes(dt.getUTCMinutes() + step)
    return dt
}

exports.hour = {
  floor: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Not all timezones align on hours! (India)
    dt = new Date(dt)
    dt.setUTCMinutes(0, 0, 0)
    return dt

  ceil: (dt, tz) ->
    throw new TypeError("#{tz} is not a valid timezone") unless isTimezone(tz)
    # Not all timezones align on hours! (India)
    dt = new Date(dt)
    if dt.getUTCMilliseconds() or dt.getUTCSeconds() or dt.getUTCMinutes()
      dt.setUTCMinutes(60, 0, 0)
    return dt

  move: (dt, tz, step) ->
    dt = new Date(dt)
    dt.setUTCHours(dt.getUTCHours() + step)
    return dt
}

exports.day = {
  floor: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), wt.getDate(), 0, 0, 0, 0)

  ceil: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    date = wt.getDate()
    date++ if wt.getMilliseconds() or wt.getSeconds() or wt.getMinutes() or wt.getHours()
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), date, 0, 0, 0, 0)

  move: (dt, tz, step) ->
    throw new TypeError("tz must be provided") unless isTimezone(tz)
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), wt.getDate() + step, wt.getHours(), wt.getMinutes(), wt.getSeconds(), wt.getMilliseconds())
}

exports.week = {
  floor: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), wt.getDate() - wt.getUTCDay(), 0, 0, 0, 0)

  ceil: (dt, tz) ->
    throw new Error("week ceil not implemented yet")

  move: (dt, tz, step) ->
    throw new TypeError("tz must be provided") unless isTimezone(tz)
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), wt.getDate() + step * 7, wt.getHours(), wt.getMinutes(), wt.getSeconds(), wt.getMilliseconds())
}

exports.month = {
  floor: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth(), 1, 0, 0, 0, 0)

  ceil: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    month = wt.getMonth()
    month++ if wt.getMilliseconds() or wt.getSeconds() or wt.getMinutes() or wt.getHours() or wt.getDate() isnt 1
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), month, 1, 0, 0, 0, 0)

  move: (dt, tz, step) ->
    throw new TypeError("tz must be provided") unless isTimezone(tz)
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), wt.getMonth() + step, wt.getDate(), wt.getHours(), wt.getMinutes(), wt.getSeconds(), wt.getMilliseconds())
}

exports.year = {
  floor: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear(), 0, 1, 0, 0, 0, 0)

  ceil: (dt, tz) ->
    wt = WallTime.UTCToWallTime(dt, tz)
    year = wt.getFullYear()
    year++ if wt.getMilliseconds() or wt.getSeconds() or wt.getMinutes() or wt.getHours() or wt.getDate() isnt 1 or wt.getMonth()
    return WallTime.WallTimeToUTC(tz, year, 0, 1, 0, 0, 0, 0)

  move: (dt, tz, step) ->
    throw new TypeError("tz must be provided") unless isTimezone(tz)
    wt = WallTime.UTCToWallTime(dt, tz)
    return WallTime.WallTimeToUTC(tz, wt.getFullYear() + step, wt.getMonth(), wt.getDate(), wt.getHours(), wt.getMinutes(), wt.getSeconds(), wt.getMilliseconds())
}


periodWeekRegExp = ///
  ^P
  (\d+)W   # week
  $
  ///

periodRegExp = ///
  ^P
  (?:(\d+)Y)?    # year
  (?:(\d+)M)?    # month
  (?:(\d+)D)?    # day
  (?:T           # T separator
    (?:(\d+)H)?  # hour
    (?:(\d+)M)?  # minute
    (?:(\d+)S)?  # second
  )?
  $
  ///

exports.durationMove = (duration) ->
  durationPart = {}
  if matches = periodWeekRegExp.exec(duration)
    matches = matches.map(Number)
    durationPart.week =    matches[1] if matches[1]

  else if matches = periodRegExp.exec(duration)
    matches = matches.map(Number)
    durationPart.year =   matches[1] if matches[1]
    durationPart.month =  matches[2] if matches[2]
    durationPart.day =    matches[3] if matches[3]
    durationPart.hour =   matches[4] if matches[4]
    durationPart.minute = matches[5] if matches[5]
    durationPart.second = matches[6] if matches[6]
  else
    throw new Error("Can not parse duration '#{duration}'")

  nonZero = false
  for k, v of durationPart
    nonZero = true
    break

  throw new Error("Must be a non zero duration") unless nonZero

  return (dt, tz, step = 1) ->
    for durationType, value of durationPart
      dt = exports[durationType].move(dt, tz, step * value)
    return dt

# ---------------------------------------------------------

`return module.exports; }).call(this,
  (typeof module === 'undefined' ? {exports: {}} : module),
  (typeof require === 'undefined' ? function (modulePath, altPath) {
    if (altPath) return window[altPath];
    var moduleParts = modulePath.split('/');
    return window[moduleParts[moduleParts.length - 1]];
  } : require)
)`
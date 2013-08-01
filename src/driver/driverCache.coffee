`(typeof window === 'undefined' ? {} : window)['driverCache'] = (function(module, require){"use strict"; var exports = module.exports`

# -----------------------------------------------------
driverUtil = require('./driverUtil')

moveTimestamp = (timestamp, period, timezone) ->
  newTimestamp = new Date(timestamp)

  switch period
    when 'PT1S'
      newTimestamp.setSeconds(newTimestamp.getSeconds() + 1)
    when 'PT1M'
      newTimestamp.setMinutes(newTimestamp.getMinutes() + 1)
    when 'PT1H'
      newTimestamp.setHours(newTimestamp.getHours() + 1)
      newTimestamp = driverUtil.adjust.hour.ceil(newTimestamp, timezone)
    when 'P1D'
      newTimestamp.setDate(newTimestamp.getDate() + 1)
      newTimestamp = driverUtil.adjust.day.ceil(newTimestamp, timezone)
    else
      throw new Error("unknown time period")

  return newTimestamp


filterToHashHelper = (filter) ->
  return switch filter.type
    when 'true'      then "T"
    when 'false'     then "F"
    when 'is'        then "IS:#{filter.attribute}:#{filter.value}"
    when 'in'        then "IN:#{filter.attribute}:#{filter.values.join(';')}"
    when 'fragments' then "F:#{filter.attribute}:#{filter.fragments.join(' ')}"
    when 'match'     then "F:#{filter.attribute}:#{filter.expression}"
    when 'within'    then "W:#{filter.attribute}:#{filter.range[0].valueOf()}:#{filter.range[1].valueOf()}"
    when 'not'       then "N(#{filterToHashHelper(filter.filter)})"
    when 'and'       then "A:(#{filter.filters.map(filterToHashHelper).join(')(')})"
    when 'or'        then "O:(#{filter.filters.map(filterToHashHelper).join(')(')})"
    else throw new Error("unsupported filter type")

filterToHash = (filter) ->
  return '' unless filter?
  hash = []
  return filterToHashHelper(driverUtil.simplifyFilter(filter))

splitToHash = (split) ->
  hash = []
  for own k, v of split
    continue if k in ['name', 'bucketFilter']
    hash.push(k + ":" + v)

  return hash.sort().join('|')

combineToHash = (combine) ->
  hash = []
  for own k, v of combine
    hash.push(k + ":" + JSON.stringify(v))

  return hash.sort().join('|')

generateHash = (filter, splitOp, combineOp) ->
  # Get Filter and Split
  return filterToHash(filter) + '&' + splitToHash(splitOp) + '&' + combineToHash(combineOp)

addToFilter = (givenFilter, timeAttribute, newFilterPieces...) ->
  if givenFilter?
    newTimeFilterPiece = newFilterPieces.filter(({attribute}) -> return attribute is timeAttribute)[0]
    if newTimeFilterPiece?
      separatedFilters = driverUtil.extractFilterByAttribute(givenFilter, timeAttribute)
      givenFilter = separatedFilters[0]
      timeFilter = separatedFilters[1]
    newFilterPieces.push givenFilter

  if newFilterPieces.length > 1
    return {
      type: 'and'
      operation: 'filter'
      filters: newFilterPieces
    }

  return newFilterPieces[0]

createFilter = (value, splitOp) ->
  if splitOp.bucket in ['timePeriod', 'timeDuration']
    newFilterPiece = {
      attribute: splitOp.attribute
      operation: 'filter'
      type: 'within'
      value: value.map((time) -> if time instanceof Date then time.toISOString() else time)
    }
  else
    newFilterPiece = {
      attribute: splitOp.attribute
      operation: 'filter'
      type: 'is'
      value
    }
  return newFilterPiece

class FilterCache
  # { key: filter,
  #   value: { key: metric,
  #            value: value } }
  constructor: (@timeAttribute) ->
    @hashmap = {}

  get: (filter) ->
    #   {
    #     <attribute>: <value>
    #     <attribute>: <value>
    #   }
    return @hashmap[filterToHash(filter)]

  put: (condensedQuery, root) -> # Recursively deconstruct root and add to cache
    @_filterPutHelper(condensedQuery, root, condensedQuery[0].filter, 0)
    return

  _filterPutHelper: (condensedQuery, node, filter, level) ->
    return unless node.prop?

    hashValue = @hashmap[filterToHash(filter)] ?= {}
    applies = condensedQuery[level].applies
    for apply in applies
      hashValue[apply.name] = node.prop[apply.name] ? hashValue[apply.name]

    if node.splits?
      splitOp = condensedQuery[level + 1].split
      for split in node.splits
        newFilter = addToFilter(filter, @timeAttribute, createFilter(split.prop[splitOp.name], splitOp))
        @_filterPutHelper(condensedQuery, split, newFilter, level + 1)
    return


class SplitCache
  # { key: filter,
  #   value: { key: split,
  #            value: [list of dimension values] } }
  constructor: (@timeAttribute) ->
    @hashmap = {}

  get: (filter, splitOp, combineOp) ->
    # Return format:
    # [
    # <value>
    # <value>
    # <value>
    # ]
    if splitOp.bucket in ['timePeriod', 'timeDuration']
      return @_timeCalculate(filter, splitOp)
    else
      hash = generateHash(filter, splitOp, combineOp)
      console.log 'GET', hash
      return @hashmap[hash]

  put: (condensedQuery, root) -> # Recursively deconstruct root and add to cache
    @_splitPutHelper(condensedQuery, root, condensedQuery[0].filter, 0)
    return

  _splitPutHelper: (condensedQuery, node, filter, level) ->
    return unless node.splits?

    splitOp = condensedQuery[level + 1].split
    combineOp = condensedQuery[level + 1].combine
    splitOpName = splitOp.name
    splitValues = node.splits.map((node) -> return node.prop[splitOpName])
    hash = generateHash(filter, splitOp, combineOp)
    console.log 'PUT', hash
    @hashmap[hash] = splitValues

    if condensedQuery[level + 2]?
      for split in node.splits
        newFilter = addToFilter(filter, @timeAttribute, createFilter(split.prop[splitOpName], splitOp))
        @_splitPutHelper(condensedQuery, split, newFilter, level + 1)
    return

  _timeCalculate: (filter, splitOp) ->
    separatedFilters = driverUtil.extractFilterByAttribute(filter, @timeAttribute)
    timeFilter = separatedFilters[1]
    timezone = splitOp.timezone or 'Etc/UTC'
    timestamps = []
    [timestamp, end] = driverUtil.convertToTimezoneJS(timeFilter.range, timezone)
    if splitOp.bucket is 'timeDuration'
      duration = splitOp.duration
      while true
        newTimestamp = new Date(timestamp.valueOf() + duration)
        break if newTimestamp > end
        timestamps.push([new Date(timestamp), new Date(newTimestamp)])
        timestamp = newTimestamp

    else if splitOp.bucket is 'timePeriod'
      while true
        newTimestamp = moveTimestamp(timestamp, splitOp.period, timezone)
        break if newTimestamp > end
        timestamps.push([new Date(timestamp), new Date(newTimestamp)])
        timestamp = newTimestamp
    else
      throw new Error("unknown time bucket")

    return timestamps


module.exports = ({driver, timeAttribute}) ->
  timeAttribute ?= 'timestamp'
  splitCache = new SplitCache(timeAttribute)
  filterCache = new FilterCache(timeAttribute)

  checkDeep = (node, currentLevel, targetLevel, name, bucketFilter) ->
    if currentLevel is targetLevel
      return node.prop[name]?

    if filteredSplitValue = node.prop[bucketFilter?.prop]
      if filteredSplitValue in bucketFilter?.values
        if node.splits?
          return node.splits.every((split) -> return checkDeep(split, currentLevel + 1, targetLevel, name))
        return false
      else
        return true

    if node.splits?
      return node.splits.every((split) -> return checkDeep(split, currentLevel + 1, targetLevel, name, bucketFilter))
    return false

  bucketFilterValueCheck = (node, currentLevel, targetLevel, bucketFilter) ->
    if currentLevel is targetLevel
      return bucketFilter.values unless node.splits?
      currentSplits = node.splits.filter(({splits}) -> return splits?).map((split) -> split.prop[bucketFilter.prop])
      return bucketFilter.values.filter((value) -> value not in currentSplits)

    if node.splits?
      return node.splits.map((split) -> return bucketFilterValueCheck(split, currentLevel + 1, targetLevel, bucketFilter))
              .reduce(((prevValue, currValue) -> prevValue.push currValue; return prevValue), [])

    return bucketFilter.values

  getUnknownQuery = (query, root, condensedQuery) ->
    return query unless root?
    unknownQuery = []
    added = false

    for condensedCommand, i in condensedQuery
      if condensedCommand.filter?
        condensedCommand.filter.operation = 'filter'
        unknownQuery.push condensedCommand.filter

      if condensedCommand.split?
        newSplit = JSON.parse(JSON.stringify(condensedCommand.split))
        if condensedCommand.split.bucketFilter?
          newValues = bucketFilterValueCheck(root, 0, i - 2, condensedCommand.split.bucketFilter)
          newSplit.bucketFilter.values = newValues
          if newValues.length > 0
            added = true
        unknownQuery.push newSplit

      if condensedCommand.combine?
        mustApply = condensedCommand.combine.sort.prop

      if condensedCommand.applies?
        for apply in condensedCommand.applies
          exists = checkDeep(root, 0, i, apply.name, condensedCommand.split?.bucketFilter)
          if not exists
            added = true

          if (apply.name is mustApply) or (not exists)
            unknownQuery.push apply

      if condensedCommand.combine?
        unknownQuery.push condensedCommand.combine

    if added
      return unknownQuery

    return null

  getKnownTreeHelper = (condensedQuery, filter, level, upperSplitValue) ->
    applies = condensedQuery[level].applies
    splitOp = condensedQuery[level + 1]?.split
    combineOp = condensedQuery[level + 1]?.combine
    filterCacheResult = filterCache.get(filter)

    prop = {}
    if filterCacheResult?
      for apply in applies
        prop[apply.name] = filterCacheResult[apply.name]

    if not splitOp? # end case
      return {
        prop
      }

    cachedValues = splitCache.get(filter, splitOp, combineOp)

    if not cachedValues?
      return {
        prop
      }

    bucketFilter = splitOp.bucketFilter
    if bucketFilter?
      if upperSplitValue not in bucketFilter.values
        return {
          prop
        }

    splits = []

    for value in cachedValues
      newFilter = addToFilter(filter, timeAttribute, createFilter(value, splitOp))
      ret = getKnownTreeHelper(condensedQuery, newFilter, level + 1, value)
      ret.prop[splitOp.name] = value
      splits.push ret

    if combineOp?.sort?
      sortProp = combineOp.sort.prop
      if combineOp.sort.direction is 'descending'
        splits.sort((a, b) ->
          if a.prop[sortProp][0]?
            return b.prop[sortProp][0] - a.prop[sortProp][0]
          return b.prop[sortProp] - a.prop[sortProp])
      else if combineOp.sort.direction is 'ascending'
        splits.sort((a, b) ->
          if a.prop[sortProp][0]?
            return a.prop[sortProp][0] - b.prop[sortProp][0]
          return a.prop[sortProp] - b.prop[sortProp])

      if combineOp.limit?
        splits.splice(combineOp.limit)

    return {
      prop
      splits
    }

  getKnownTree = (condensedQuery) ->
    return getKnownTreeHelper(condensedQuery, condensedQuery[0].filter, 0)

  convertEmptyTreeToEmptyObject = (tree) ->
    propKeys = (key for key, value of tree.prop)
    return {} if (propKeys.length is 0 and not tree.splits?)
    return tree


  return (request, callback) ->
    throw new Error("request not supplied") unless request
    {context, query} = request
    async = query

    try
      condensedQuery = driverUtil.condenseQuery(query)
    catch e
      callback(e)
      return

    # If there is a split for continuous dimension, don't use cache. Doable. but not now
    if condensedQuery[1]?.split?.bucket in ['continuous', 'tuple']
      return driver({query}, callback)

    root = getKnownTree(condensedQuery)
    unknownQuery = getUnknownQuery(query, root, condensedQuery)
    if not unknownQuery?
      callback(null, root)
      return

    return driver {context, query: unknownQuery}, (err, root) ->
      if err?
        callback(err, null)
        return

      splitCache.put(condensedQuery, root)
      filterCache.put(condensedQuery, root)
      knownTree = convertEmptyTreeToEmptyObject(getKnownTree(condensedQuery))
      callback(null, knownTree)
    return



# -----------------------------------------------------
# Handle commonJS crap
`return module.exports; }).call(this,
  (typeof module === 'undefined' ? {exports: {}} : module),
  (typeof require === 'undefined' ? function (modulePath) {
    var moduleParts = modulePath.split('/');
    return window[moduleParts[moduleParts.length - 1]];
  } : require)
)`

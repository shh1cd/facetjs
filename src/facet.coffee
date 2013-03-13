
arraySubclass = if [].__proto__
    # Until ECMAScript supports array subclassing, prototype injection works well.
    (array, prototype) ->
      array.__proto__ = prototype
      return array
  else
    # And if your browser doesn't support __proto__, we'll use direct extension.
    (array, prototype) ->
      array[property] = prototype[property] for property in prototype
      return array


flatten = (ar) -> Array::concat.apply([], ar)

# =============================================================

class Interval
  constructor: (@start, @end) ->
    return

  transform: (fn) ->
    null

  valueOf: ->
    return @end - @start

Interval.fromArray = (arr) ->
  throw new Error("Interval must have length of 2 (is: #{arr.length})") unless arr.length is 2
  [start, end] = arr
  startType = typeof start
  endType = typeof end
  if startType is 'string' and endType is 'string'
    startDate = new Date(start)
    throw new Error("bad start date '#{start}'") if isNaN(startDate.valueOf())
    endDate = new Date(end)
    throw new Error("bad end date '#{end}'") if isNaN(endDate.valueOf())
    return new Interval(startDate, endDate)

  return new Interval(start, end)


isValidStage = (stage) ->
  return Boolean(stage and typeof stage.type is 'string' and stage.node)

class Segment
  constructor: ({ @parent, stage, @prop, @splits }) ->
    throw "invalid stage" unless isValidStage(stage)
    @_stageStack = [stage]
    @scale = {}

  getStage: ->
    return @_stageStack[@_stageStack.length - 1]

  setStage: (stage) ->
    throw "invalid stage" unless isValidStage(stage)
    @_stageStack[@_stageStack.length - 1] = stage
    return

  pushStage: (stage) ->
    throw "invalid stage" unless isValidStage(stage)
    @_stageStack.push(stage)
    return

  popStage: ->
    throw "must have at least one stage" if @_stageStack.length < 2
    @_stageStack.pop()
    return


window.facet = facet = {}

# =============================================================
# SPLIT
# A split is a function that takes a row and returns a string-able thing.

facet.split = {
  identity: (attribute) -> {
      bucket: 'identity'
      attribute
    }

  continuous: (attribute, size, offset) -> {
      bucket: 'continuous'
      attribute
      size
      offset
    }

  time: (attribute, duration) ->
    throw new Error("Invalid duration '#{duration}'") unless duration in ['second', 'minute', 'hour', 'day']
    return {
      bucket: 'time'
      attribute
      duration
    }
}

# =============================================================
# APPLY
# An apply is a function that takes an array of rows and returns a number.

facet.apply = {
  count: -> {
    aggregate: 'count'
  }

  sum: (attribute) -> {
    aggregate: 'sum'
    attribute
  }

  average: (attribute) -> {
    aggregate: 'average'
    attribute
  }

  min: (attribute) -> {
    aggregate: 'min'
    attribute
  }

  max: (attribute) -> {
    aggregate: 'max'
    attribute
  }

  unique: (attribute) -> {
    aggregate: 'unique'
    attribute
  }
}

# =============================================================
# USE
# Extracts the property and other things from a segment

wrapLiteral = (arg) ->
  return if typeof arg in ['undefined', 'function'] then arg else facet.use.literal(arg)

getProp = (segment, propName) ->
  if not segment
    throw new Error("No such prop '#{propName}'")
  return segment.prop[propName] ? getProp(segment.parent, propName)

getScale = (segment, scaleName) ->
  if not segment
    throw new Error("No such scale '#{scaleName}'")
  return segment.scale[scaleName] ? getScale(segment.parent, scaleName)

facet.use = {
  prop: (propName) -> (segment) ->
    return getProp(segment, propName)

  literal: (value) -> () ->
    return value

  fn: (args..., fn) -> (segment) ->
    throw new TypeError("second argument must be a function") unless typeof fn is 'function'
    return fn.apply(this, args.map((arg) -> arg(segment)))

  scale: (scaleName, use) -> (segment) ->
    scale = getScale(segment, scaleName)
    throw new Error("'#{scaleName}' scale is untrained") if scale.train
    use or= scale.use
    return scale.fn(use(segment))

  interval: (start, end) ->
    start = wrapLiteral(start)
    end = wrapLiteral(end)
    return (segment) -> new Interval(start(segment), end(segment))
}

# =============================================================
# LAYOUT
# A function that takes a rectangle and a lists of facets and initializes their node. (Should be generalized to any shape).

divideLength = (length, sizes) ->
  totalSize = 0
  totalSize += size for size in sizes
  lengthPerSize = length / totalSize
  return sizes.map((size) -> size * lengthPerSize)

stripeTile = (dim1, dim2) -> ({ gap, size } = {}) ->
  gap or= 0
  size = wrapLiteral(size ? 1)

  return (parentSegment, segmentGroup) ->
    n = segmentGroup.length
    parentStage = parentSegment.getStage()
    if parentStage.type isnt 'rectangle'
      throw new Error("Must have a rectangular stage (is #{parentStage.type})")
    parentDim1 = parentStage[dim1]
    parentDim2 = parentStage[dim2]
    maxGap = Math.max(0, (parentDim1 - n * 2) / (n - 1)) # Each segment takes up at least 2px
    gap = Math.min(gap, maxGap)
    availableDim1 = parentDim1 - gap * (n - 1)
    dim1s = divideLength(availableDim1, segmentGroup.map(size))

    dimSoFar = 0
    return segmentGroup.map((segment, i) ->
      curDim1 = dim1s[i]

      psudoStage = {
        type: 'rectangle'
        x: 0
        y: 0
      }
      psudoStage[if dim1 is 'width' then 'x' else 'y'] = dimSoFar
      psudoStage[dim1] = curDim1
      psudoStage[dim2] = parentDim2

      dimSoFar += curDim1 + gap
      return psudoStage
    )

facet.layout = {
  overlap: () -> {}

  horizontal: stripeTile('width', 'height')

  vertical: stripeTile('height', 'width')

  tile: ->
    return
}

# =============================================================
# SCALE
# A function that makes a scale and adds it to the segment.
# Arguments* -> Segment -> void

facet.scale = {
  linear: ({nice}) -> (segments, {include, domain, range}) ->
    domain = wrapLiteral(domain)

    if range in ['width', 'height']
      rangeFn = (segment) -> [0, segment.getStage()[range]]
    else if typeof range is 'number'
      rangeFn = -> [0, range]
    else if Array.isArray(range) and range.length is 2
      rangeFn = -> range
    else
      throw new Error("bad range")

    domainMin = Infinity
    domainMax = -Infinity
    rangeFrom = -Infinity
    rangeTo = Infinity

    if include?
      domainMin = Math.min(domainMin, include)
      domainMax = Math.max(domainMax, include)

    for segment in segments
      domainValue = domain(segment)
      domainMin = Math.min(domainMin, domainValue)
      domainMax = Math.max(domainMax, domainValue)

      rangeValue = rangeFn(segment)
      rangeFrom = rangeValue[0]
      rangeTo = Math.min(rangeTo, rangeValue[1])

    if not (isFinite(domainMin) and isFinite(domainMax) and isFinite(rangeFrom) and isFinite(rangeTo))
      throw new Error("we went into infinites")

    scaleFn = d3.scale.linear()
      .domain([domainMin, domainMax])
      .range([rangeFrom, rangeTo])

    if nice
      scaleFn.nice()

    return {
      fn: scaleFn
      use: domain
    }

  log: ({plusOne}) -> (segments, {domain, range, include}) ->
    domain = wrapLiteral(domain)

    if range in ['width', 'height']
      rangeFn = (segment) -> [0, segment.getStage()[range]]
    else if typeof range is 'number'
      rangeFn = -> [0, range]
    else if Array.isArray(range) and range.length is 2
      rangeFn = -> range
    else
      throw new Error("bad range")

    domainMin = Infinity
    domainMax = -Infinity
    rangeFrom = -Infinity
    rangeTo = Infinity

    if include?
      domainMin = Math.min(domainMin, include)
      domainMax = Math.max(domainMax, include)

    for segment in segments
      domainValue = domain(segment)
      domainMin = Math.min(domainMin, domainValue)
      domainMax = Math.max(domainMax, domainValue)

      rangeValue = rangeFn(segment)
      rangeFrom = rangeValue[0]
      rangeTo = Math.min(rangeTo, rangeValue[1])

    if not (isFinite(domainMin) and isFinite(domainMax) and isFinite(rangeFrom) and isFinite(rangeTo))
      throw new Error("we went into infinites")

    return {
      fn: d3.scale.log().domain([domainMin, domainMax]).range([rangeFrom, rangeTo])
      use: domain
    }

  color: () -> (segments, {domain}) ->
    domain = wrapLiteral(domain)

    return {
      fn: d3.scale.category10().domain(segments.map(domain))
      use: domain
    }
}

# =============================================================
# TRANSFORM STAGE
# A function that transforms the stage from one form to another.
# Arguments* -> Segment -> void

boxPosition = (segment, stageWidth, left, width, right) ->
  if left and width and right
    throw new Error("Over-constrained")

  if left
    leftValue = left(segment)
    if leftValue instanceof Interval
      throw new Error("Over-constrained by width") if width
      return [leftValue.start, leftValue.end - leftValue.start]
    else
      if width
        widthValue = width(segment).valueOf()
        return [leftValue, widthValue]
      else
        return [leftValue, stageWidth - leftValue]
  else if right
    rightValue = right(segment)
    if rightValue instanceof Interval
      throw new Error("Over-constrained by width") if width
      return [stageWidth - rightValue.start, rightValue.end - rightValue.start]
    else
      if width
        widthValue = width(segment).valueOf()
        return [stageWidth - rightValue - widthValue, widthValue]
      else
        return [0, stageWidth - rightValue]
  else
    if width
      widthValue = width(segment).valueOf()
      return [(stageWidth - widthValue) / 2, widthValue]
    else
      return [0, stageWidth]


facet.transform = {
  point: {
    point: ->
      throw "not implemented yet"

    line: ({length}) ->
      throw "not implemented yet"

    rectangle: ->
      throw "not implemented yet"
  }

  line: {
    point: ->
      throw "not implemented yet"

    line: ->
      throw "not implemented yet"

    rectangle: ->
      throw "not implemented yet"
  }

  rectangle: {
    point: ({left, right, top, bottom} = {}) ->
      left = wrapLiteral(left)
      right = wrapLiteral(right)
      top = wrapLiteral(top)
      bottom = wrapLiteral(bottom)

      # Make sure we are not over-constrained
      if (left and right) or (top and bottom)
        throw new Error("Over-constrained")

      fx = if left then (w, s) -> left(s) else if right  then (w, s) -> w - right(s)  else (w, s) -> w / 2
      fy = if top  then (h, s) -> top(s)  else if bottom then (h, s) -> h - bottom(s) else (h, s) -> h / 2

      return (segment) ->
        stage = segment.getStage()
        throw new Error("Must have a rectangle stage (is #{stage.type})") unless stage.type is 'rectangle'

        return {
          type: 'point'
          x: fx(stage.width, segment)
          y: fy(stage.height, segment)
        }

    line: ->
      throw "not implemented yet"

    rectangle: ->
      throw "not implemented yet"
  }

  polygon: {
    point: ->
      throw "not implemented yet"

    polygon: ->
      throw "not implemented yet"
  }

  # margin: ({left, width, right, top, height, bottom}) -> (segment) ->
  #   stage = segment.getStage()
  #   throw new Error("Must have a rectangle stage (is #{stage.type})") unless stage.type is 'rectangle'

  #   [x, w] = boxPosition(segment, stage.width, left, width, right)
  #   [y, h] = boxPosition(segment, stage.height, top, height, bottom)

  # move

  # rotate
}

# =============================================================
# PLOT
# A function that takes a facet and
# Arguments* -> Segment -> void

facet.plot = {
  rect: ({left, width, right, top, height, bottom, stroke, fill, opacity}) ->
    left = wrapLiteral(left)
    width = wrapLiteral(width)
    right = wrapLiteral(right)
    top = wrapLiteral(top)
    height = wrapLiteral(height)
    bottom = wrapLiteral(bottom)
    fill = wrapLiteral(fill)
    opacity = wrapLiteral(opacity)

    return (segment) ->
      stage = segment.getStage()
      throw new Error("Must have a rectangle stage (is #{stage.type})") unless stage.type is 'rectangle'

      [x, w] = boxPosition(segment, stage.width, left, width, right)
      [y, h] = boxPosition(segment, stage.height, top, height, bottom)

      stage.node.append('rect').datum(segment)
        .attr('x', x)
        .attr('y', y)
        .attr('width', w)
        .attr('height', h)
        .style('fill', fill)
        .style('stroke', stroke)
        .style('opacity', opacity)
      return

  text: ({color, text, size, anchor, baseline, angle}) ->
    color = wrapLiteral(color)
    text = wrapLiteral(text)
    size = wrapLiteral(size)
    anchor = wrapLiteral(anchor)
    baseline = wrapLiteral(baseline)
    angle = wrapLiteral(angle)

    return (segment) ->
      stage = segment.getStage()
      throw new Error("Must have a point stage (is #{stage.type})") unless stage.type is 'point'
      myNode = stage.node.append('text').datum(segment)

      if angle
        myNode.attr('transform', "rotate(#{angle(segment)})")

      if baseline
        myNode.attr('dy', (segment) ->
          baselineValue = baseline(segment)
          return if baselineValue is 'top' then '.71em' else if baselineValue is 'center' then '.35em' else null
        )

      myNode
        .style('font-size', size)
        .style('fill', color)
        .style('text-anchor', anchor)
        .text(text)
      return

  circle: ({radius, stroke, fill}) ->
    radius = wrapLiteral(radius)
    stroke = wrapLiteral(stroke)
    fill = wrapLiteral(fill)

    return (segment) ->
      stage = segment.getStage()
      throw new Error("Must have a point stage (is #{stage.type})") unless stage.type is 'point'
      stage.node.append('circle').datum(segment)
        .attr('r', radius)
        .style('fill', fill)
        .style('stroke', stroke)
      return
}

# =============================================================
# SORT

facet.sort = {
  natural: (attribute, direction = 'descending') -> {
    compare: 'natural'
    attribute
    direction
  }

  caseInsensetive: (attribute, direction = 'descending') -> {
    compare: 'caseInsensetive'
    attribute
    direction
  }
}


# =============================================================
# main

class FacetJob
  constructor: (@selector, @width, @height, @driver) ->
    @ops = []
    @knownProps = {}

  split: (propName, split) ->
    split = _.clone(split)
    split.operation = 'split'
    split.prop = propName
    @ops.push(split)
    @knownProps[propName] = true
    return this

  layout: (layout) ->
    throw new TypeError("layout must be a function") unless typeof layout is 'function'
    @ops.push({
      operation: 'layout'
      layout
    })
    return this

  apply: (propName, apply) ->
    apply = _.clone(apply)
    apply.operation = 'apply'
    apply.prop = propName
    @ops.push(apply)
    @knownProps[propName] = true
    return this

  scale: (name, scale) ->
    throw new TypeError("scale must be a function") unless typeof scale is 'function'
    @ops.push({
      operation: 'scale'
      name
      scale
    })
    return this

  train: (name, param) ->
    @ops.push({
      operation: 'train'
      name
      param
    })
    return this

  combine: ({ filter, sort, limit } = {}) ->
    # ToDo: implement filter
    combine = {
      operation: 'combine'
    }
    if sort
      if not @knownProps[sort.prop]
        throw new Error("can not sort on unknown prop '#{sort.prop}'")
      combine.sort = sort
      combine.sort.compare ?= 'natural'

    if limit?
      combine.limit = limit

    @ops.push(combine)
    return this

  transform: (transform) ->
    throw new TypeError("transform must be a function") unless typeof transform is 'function'
    @ops.push({
      operation: 'transform'
      transform
    })
    return this

  untransform: ->
    @ops.push({
      operation: 'untransform'
    })
    return this


  plot: (plot) ->
    throw new TypeError("plot must be a function") unless typeof plot is 'function'
    @ops.push({
      operation: 'plot'
      plot
    })
    return this

  getQuery: ->
    return @ops.filter(({operation}) -> operation in ['split', 'apply', 'combine'])

  render: ->
    parent = d3.select(@selector)
    width = @width
    height = @height
    throw new Error("could not find the provided selector") if parent.empty()

    svg = parent.append('svg')
      .attr('width', width)
      .attr('height', height)

    operations = @ops
    @driver @getQuery(), (err, res) ->
      if err
        alert("An error has occurred: " + if typeof err is 'string' then err else err.message)
        return

      segmentGroups = [[new Segment({
        parent: null
        stage: {
          node: svg
          type: 'rectangle'
          width
          height
        }
        prop: res.prop
        splits: res.splits
      })]]

      for cmd in operations
        switch cmd.operation
          when 'split'
            segmentGroups = flatten(segmentGroups).map((segment) ->
              return segment.splits = segment.splits.map ({ prop, splits }) ->
                stage = _.clone(segment.getStage())
                stage.node = stage.node.append('g')
                for key, value of prop
                  if Array.isArray(value)
                    prop[key] = Interval.fromArray(value)
                return new Segment({
                  parent: segment
                  stage: stage
                  prop
                  splits
                })
            )

          when 'apply', 'combine'
            null # Do nothing, there is nothing to do on the renderer for those two :-)

          when 'scale'
            { name, scale } = cmd
            for segmentGroup in segmentGroups
              for segment in segmentGroup
                segment.scale[name] = {
                  train: scale
                }

          when 'train'
            { name, param } = cmd

            sourceSegment = segmentGroups[0][0]
            hops = 0
            while true
              break if sourceSegment.scale[name]
              sourceSegment = sourceSegment.parent
              hops++
              throw new Error("can not find scale '#{name}'") unless sourceSegment

            # Get all of sources children on my level (my cousins)
            unifiedSegments = [sourceSegment]
            while hops > 0
              unifiedSegments = flatten(unifiedSegments.map((s) -> s.splits))
              hops--

            if not sourceSegment.scale[name].train
              throw new Error("Scale '#{name}' already trained")

            sourceSegment.scale[name] = sourceSegment.scale[name].train(unifiedSegments, param)

          when 'layout'
            { layout } = cmd
            for segmentGroup in segmentGroups
              parentSegment = segmentGroup[0].parent
              throw new Error("You must split before calling layout") unless parentSegment
              psudoStages = layout(parentSegment, segmentGroup)
              for segment, i in segmentGroup
                psudoStage = psudoStages[i]
                stageX = psudoStage.x
                stageY = psudoStage.y
                stage = segment.getStage()
                delete psudoStage.x
                delete psudoStage.y
                psudoStage.node = stage.node
                  .attr('transform', "translate(#{stageX},#{stageY})")
                segment.setStage(psudoStage)

          when 'transform'
            { transform } = cmd
            for segmentGroup in segmentGroups
              for segment in segmentGroup
                psudoStage = transform(segment)
                stageX = psudoStage.x
                stageY = psudoStage.y
                stage = segment.getStage()
                delete psudoStage.x
                delete psudoStage.y
                psudoStage.node = stage.node.append('g')
                  .attr('transform', "translate(#{stageX},#{stageY})")
                segment.pushStage(psudoStage)


          when 'untransform'
            for segmentGroup in segmentGroups
              for segment in segmentGroup
                segment.popStage()

          when 'plot'
            { plot } = cmd
            for segmentGroup in segmentGroups
              for segment in segmentGroup
                plot(segment)

          else
            throw new Error("Unknown operation '#{cmd.operation}'")

      return

    return this


facet.define = (selector, width, height, driver) ->
  throw new Error("bad size: #{width} x #{height}") unless width and height
  return new FacetJob(selector, width, height, driver)


facet.ajaxPoster = ({url, context, prety}) -> (query, callback) ->
  return $.ajax({
    url
    type: 'POST'
    dataType: 'json'
    contentType: 'application/json'
    data: JSON.stringify({ context, query }, null, if prety then 2 else null)
    success: (res) ->
      callback(null, res)
      return
    error: (xhr) ->
      text = xhr.responseText
      try
        err = JSON.parse(text)
      catch e
        err = { message: text }
      callback(err, null)
      return
  })

facet.verboseProxy = (driver) -> (query, callback) ->
  console.log('Query:', query)
  driver(query, (err, res) ->
    console.log('Result:', res)
    callback(err, res)
    return
  )
  return

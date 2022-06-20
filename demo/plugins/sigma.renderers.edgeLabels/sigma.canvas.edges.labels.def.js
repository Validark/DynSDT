;(function(undefined) {
  'use strict';

  if (typeof sigma === 'undefined')
    throw 'sigma is not declared';

  // Initialize packages:
  sigma.utils.pkg('sigma.canvas.edges.labels');

  /**
   * This label renderer will just display the label on the line of the edge.
   * The label is rendered at half distance of the edge extremities, and is
   * always oriented from left to right on the top side of the line.
   *
   * @param  {object}                   edge         The edge object.
   * @param  {object}                   source node  The edge source node.
   * @param  {object}                   target node  The edge target node.
   * @param  {CanvasRenderingContext2D} context      The canvas context.
   * @param  {configurable}             settings     The settings function.
   */
  sigma.canvas.edges.labels.def =
    function(edge, source, target, context, settings) {
    if (typeof edge.label !== 'string' || source == target)
      return;

    var prefix = settings('prefix') || '',
        size = edge[prefix + 'size'] || 1;

    if (size < settings('edgeLabelThreshold'))
      return;

    if (0 === settings('edgeLabelSizePowRatio'))
      throw '"edgeLabelSizePowRatio" must not be 0.';

    var fontSize,
        x = (source[prefix + 'x'] + target[prefix + 'x']) / 2,
        y = (source[prefix + 'y'] + target[prefix + 'y']) / 2,
        dX = target[prefix + 'x'] - source[prefix + 'x'],
        dY = target[prefix + 'y'] - source[prefix + 'y'],
        sign = (source[prefix + 'x'] < target[prefix + 'x']) ? 1 : -1,
        angle = Math.atan2(dY * sign, dX * sign);

    // The font size is sublinearly proportional to the edge size, in order to
    // avoid very large labels on screen.
    // This is achieved by f(x) = x * x^(-1/ a), where 'x' is the size and 'a'
    // is the edgeLabelSizePowRatio. Notice that f(1) = 1.
    // The final form is:
    // f'(x) = b * x * x^(-1 / a), thus f'(1) = b. Application:
    // fontSize = defaultEdgeLabelSize if edgeLabelSizePowRatio = 1
    fontSize = (settings('edgeLabelSize') === 'fixed') ?
      settings('defaultEdgeLabelSize') :
      settings('defaultEdgeLabelSize') *
      size *
      Math.pow(size, -1 / settings('edgeLabelSizePowRatio'));
	// console.log(fontSize, settings('edgeLabelSize'),settings('defaultEdgeLabelSize'), settings('edgeLabelSizePowRatio'),size)
    context.save();

	// if (edge.targetLabel === 2)
	// fontSize -= 8

	// if (edge.targetLabel)
	// 	fontSize -= 4

    if (edge.active) {
      context.font = [
        settings('activeFontStyle') || settings('fontStyle'),
        fontSize + 'px',
        settings('activeFont') || settings('font')
      ].join(' ');

      context.fillStyle =

	  +edge.active > 0.5 && settings('edgeActiveColor') === 'edge' ?
        (edge.active_color || settings('defaultEdgeActiveColor')) :
        settings('defaultEdgeLabelActiveColor');
    }
    else {
      context.font = [
        settings('fontStyle'),
        fontSize + 'px',
        settings('font')
      ].join(' ');

      context.fillStyle =
        (settings('edgeLabelColor') === 'edge') ?
        (edge.color || settings('defaultEdgeColor')) :
        settings('defaultEdgeLabelColor');
    }

	// var nodeSize = node[prefix + 'size'];
	// var scalar = nodeSize / 7.627700713964738;

	// fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
	// fill_y = Math.round(node[prefix + 'y'] )
	// fill_x += 10*scalar
	// fill_y -= 15*scalar

	let fill_x, fill_y

	let label = '   ' + edge.label + ' ';
	// (edge.targetLabel === 2 ? " " : "")



	if (edge.targetLabel === 6) {
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] - nodeSize )
		fill_x -= 34*scalar
		fill_y -= 7*scalar
		// fill_x = 0;
		// fill_y = (-size / 2)

		context.textAlign = 'center';
		context.textBaseline = 'center';
	}
	else if (edge.targetLabel === 5) {
		context.textAlign = 'center';
		context.textBaseline = 'middle';
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] )
		// fill_x -= scalar
		fill_y += 15*scalar
		context.textAlign = 'right';
	}
	else if (edge.targetLabel === 4) {
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] - nodeSize )
		fill_x += 12*scalar
		fill_y -= 7*scalar
		// fill_x = 0;
		// fill_y = (-size / 2)

		context.textAlign = 'center';
		context.textBaseline = 'center';

	}
	else if (edge.targetLabel === 3) {
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] )
		fill_x += 12*scalar
		fill_y += 25*scalar
		// fill_x = 0;
		// fill_y = (-size / 2)

		context.textAlign = 'center';
		context.textBaseline = 'middle';
	} else if (edge.targetLabel === 2) {

		// const node = target
		// const nodeSize = node[prefix + 'size'];
		// const scalar = nodeSize / 7.627700713964738;

		// fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		// fill_y = Math.round(node[prefix + 'y'] )
		// // fill_x -= scalar
		// fill_y -= 15*scalar
		// fill_x = 0;
		// fill_y = (-size / 2)
		context.textAlign = 'center';
		context.textBaseline = 'middle';
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] )
		// fill_x -= scalar
		fill_y -= 15*scalar
		context.textAlign = 'right';
		// context.translate(
		// 	target[prefix + 'x'],
		// 	target[prefix + 'y'] + target[prefix + "size"] + size*12);
	} else if (edge.targetLabel === 1) {
		const node = target
		const nodeSize = node[prefix + 'size'];
		const scalar = nodeSize / 7.627700713964738;

		fill_x = Math.round(node[prefix + 'x'] - nodeSize); //+ backChars*backCharWidth
		fill_y = Math.round(node[prefix + 'y'] )
		// fill_x += 12*scalar
		fill_y -= 40*scalar
		context.textAlign = 'center';
	}
	else {
		// const node = target
		// const nodeSize = node[prefix + 'size'];
		// const scalar = nodeSize / 7.627700713964738;

		context.translate(x, y)
		fill_x = 0;
		fill_y = (-size / 2)


		// fill_y -= 40*scalar
		label = label.slice(2)

		context.textAlign = 'center';
		context.textBaseline = 'middle';

		// fill_y += fontSize
		// context.translate(target[prefix + 'x'] - target[prefix + "size"] - size*6, target[prefix + 'y'] - target[prefix + "size"] - size*12);

		// fill_x = Math.round(node[prefix + 'x'] - size); //+ backChars*backCharWidth
		// fill_y = Math.round(node[prefix + 'y'] + fontSize / 3)
		// fill_x -= backChars * backCharWidth + 7*width/12
	}

	// x = (source[prefix + 'x'] + target[prefix + 'x']) / 2,
	// y = (source[prefix + 'y'] + target[prefix + 'y']) / 2,

	// context.rotate(angle)
	const { fillStyle } = context;
	context.fillStyle = BACKGROUND_COLOR
//
//
	// console.log({edge, source, target, context})
	// context.textAlign = "bottom"

	context.save();
	context.font = [
		(edge.active && settings('activeFontStyle')) || settings('fontStyle'),
		(fontSize) + 'px',
		(edge.active && settings('activeFont')) || settings('font')
	].join(' ');
	if (!edge.doNotBack)
		context.fillText("\u{2588}".repeat(Math.ceil(context.measureText(label).width / context.measureText("\u{2588}").width)), fill_x, fill_y);
	context.restore()
	context.fillStyle = fillStyle;
    context.fillText(label, fill_x, fill_y);
    context.restore();

	// target[prefix + 'x']
	// target[prefix + 'y']
  };
}).call(this);

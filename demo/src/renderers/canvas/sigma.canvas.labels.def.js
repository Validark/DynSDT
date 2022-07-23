;(function(undefined) {
  'use strict';
  if (typeof sigma === 'undefined')
    throw 'sigma is not declared';

  // Initialize packages:
  sigma.utils.pkg('sigma.canvas.labels');

  /**
   * This label renderer will just display the label on the right of the node.
   *
   * @param  {object}                   node     The node object.
   * @param  {CanvasRenderingContext2D} context  The canvas context.
   * @param  {configurable}             settings The settings function.
   */
  sigma.canvas.labels.def = function(node, context, settings) {
    var fontSize,
        prefix = settings('prefix') || '',
        size = node[prefix + 'size'];

	let label = node.label;

	if (node.isRoot)
		label = "(0, “wikipedia”)"
	else if (node.forceLabel === 4) {
		label = label.split(":")[0]
	}
	else if (node.forceLabel)
		label = label.split(":")[1]
	else if (size < settings('labelThreshold'))
      return;

    if (!node.label || typeof node.label !== 'string')
      return;

    fontSize = (settings('labelSize') === 'fixed') ?
      settings('defaultLabelSize') :
      settings('labelSizeRatio') * size;
	var scalar = size / 7.627700713964738

	// if (node.forceLabel !== 4) {
	// 	fontSize -= 8
	// } else
	if (node.isRoot)
		fontSize -= 2
	else
		fontSize -= 3

	// if (node.forceLabel >= 5)
	// 	fontSize -= 2

    context.font = (settings('fontStyle') ? settings('fontStyle') + ' ' : '') +
      (fontSize) + 'px ' + settings('font');
    context.fillStyle = (settings('labelColor') === 'node') ?
      (node.color || settings('defaultNodeColor')) :
      settings('defaultLabelColor');

    // context.textAlign = 'center';
    // context.textBaseline = 'middle';

    // context.translate(x, y);
    // context.rotate(angle);
	const { fillStyle } = context;
	context.fillStyle = BACKGROUND_COLOR

	label = ' ' + label + ' ';
	const width = context.measureText(label).width
	const backCharWidth = context.measureText("\u{2588}").width
	const backChars = Math.floor(width / backCharWidth)

	let fill_x = Math.round(node[prefix + 'x'] - size);
	let fill_y = Math.round(node[prefix + 'y'] )

	if (node.forceLabel === 4)
	{
		fill_x -= backChars * backCharWidth + 7*width/12
	}
	else if (node.forceLabel === 5)
	{
		fill_x += 14*scalar
		fill_y -= 15*scalar
	}
	else if (node.forceLabel === 6)
	{
		context.textAlign = 'right';

		fill_x -= 0*scalar
		fill_y += 5*scalar
	}
	else if (node.forceLabel === 7)
	{
		context.textAlign = 'left';

		fill_x += 18*scalar
		fill_y += 7.5*scalar
	}
	else if (node.forceLabel === 8)
	{
		context.textAlign = 'center';

		fill_x += 8*scalar
		fill_y += 35*scalar
	}
	else if (node.forceLabel === 9)
	{
		context.textAlign = 'center';

		fill_x += 8*scalar
		fill_y -= 15*scalar
	}
	else if (node.forceLabel === 10)
	{
		context.textAlign = 'left';

		fill_x += 17*scalar
		fill_y += 28*scalar
	}
	else if (node.forceLabel === 11)
	{
		context.textAlign = 'center';

		fill_x += -8*scalar
		fill_y += 35*scalar
	}
	else if (node.forceLabel === 12)
	{
		context.textAlign = 'center';

		fill_x += 25*scalar
		fill_y += 35*scalar
	}
	else if (node.forceLabel === 13)
	{
		context.textAlign = 'center';

		fill_x += -20*scalar
		fill_y += 35*scalar
	}
	else if (node.forceLabel === 14)
	{
		context.textAlign = 'left';

		fill_x += 0*scalar
		fill_y -= 15*scalar
	}
	else
	{
		fill_x += 10*scalar
		fill_y -= 15*scalar
	}


	context.font = (settings('fontStyle') ? settings('fontStyle') + ' ' : '') +
	fontSize + 'px ' + settings('font');
	// context.fillText("\u{2588}".repeat(backChars), fill_x, fill_y)
	context.fillStyle = fillStyle;


	// if (context.textAlign === "left" || context.textAlign === "start")
	// 	fill_x += (backCharWidth * backChars - width)
	// else if (context.textAlign === "right" || context.textAlign === "end")
	// 	fill_x -= (backCharWidth * backChars - width)*1.15


	if (node.forceLabel) {
		context.save()
		if (node.color === undefined)
			throw "Node has no color"

		context.fillStyle = node.color
		// context.font = /*"bold " + */context.font
		// if (node.forceLabel >= 5)
		// {
		// 	context.fillStyle = ORIGINAL_COLOR
		// 	context.font = context.font
		// }
		// else if (node.forceLabel & 1)
		// {
		// 	context.fillStyle = SELECTED_COLOR
		//
		// }
		// else
		// {
		// 	context.fillStyle = DISABLED_COLOR
		// }
		context.fillText(label, fill_x, fill_y);
		context.restore()
	} else
	    context.fillText(label, fill_x, fill_y);
  };
}).call(this);

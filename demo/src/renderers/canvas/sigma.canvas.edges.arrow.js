;(function() {
  'use strict';

  sigma.utils.pkg('sigma.canvas.edges');

  /**
   * This edge renderer will display edges as arrows going from the source node
   *
   * @param  {object}                   edge         The edge object.
   * @param  {object}                   source node  The edge source node.
   * @param  {object}                   target node  The edge target node.
   * @param  {CanvasRenderingContext2D} context      The canvas context.
   * @param  {configurable}             settings     The settings function.
   */
  sigma.canvas.edges.arrow = function(edge, source, target, context, settings) {
    var active = edge.active,
		color = active ?
		edge.active_color || settings('defaultEdgeActiveColor') :
		edge.color,
        prefix = settings('prefix') || '',
        edgeColor = settings('edgeColor'),
        defaultNodeColor = settings('defaultNodeColor'),
        defaultEdgeColor = settings('defaultEdgeColor'),
        size = edge[prefix + 'size'] || 1,
        tSize = target[prefix + 'size'], // + 1  ?
        sX = source[prefix + 'x'],
        sY = source[prefix + 'y'],
        tX = target[prefix + 'x'],
        tY = target[prefix + 'y'],
        aSize = Math.max(size * 2.5, settings('minArrowSize')),
        d = Math.sqrt(Math.pow(tX - sX, 2) + Math.pow(tY - sY, 2)),
        aX = sX + (tX - sX) * (d - aSize - tSize) / d,
        aY = sY + (tY - sY) * (d - aSize - tSize) / d,
        vX = (tX - sX) * aSize / d,
        vY = (tY - sY) * aSize / d;

    if (!color)
      switch (edgeColor) {
        case 'source':
          color = source.color || defaultNodeColor;
          break;
        case 'target':
          color = target.color || defaultNodeColor;
          break;
        default:
          color = defaultEdgeColor;
          break;
      }

	if (active) {
		context.strokeStyle = settings('edgeActiveColor') === 'edge'
			? (color || defaultEdgeColor)
			: settings('defaultEdgeActiveColor');
	}
	else {
		context.strokeStyle = color;
	}
	context.lineWidth = size;

	if (typeof active === "number") {
		context.strokeStyle = settings('defaultEdgeActiveColor');
	}
    context.beginPath();
    context.moveTo(sX, sY);
    context.lineTo(aX, aY);
	context.stroke();

	context.fillStyle = color;
	if (typeof active === "number") {
		context.fillStyle = settings('defaultEdgeActiveColor');
	}
    context.beginPath();
    context.moveTo(aX + vX, aY + vY);
	context.lineTo(aX + vY * 0.6, aY - vX * 0.6);
    context.lineTo(aX - vY * 0.6, aY + vX * 0.6);
    context.lineTo(aX + vX, aY + vY);
    context.closePath();
    context.fill();

	if (typeof active === "number") {
		// assume its (0, 1]
		// let x, y, x2, y2;
		// if (tX > sX) {
		// 	x = tX
		// 	y = tY
		// 	x2 = sX
		// 	y2 = sY
		// } else {
		// 	x = sX
		// 	y = sY
		// 	x2 = tX
		// 	y2 = tY
		// }

		context.save()
		const dx = tX - sX
		const dy = tY - sY
		// console.log(dx, dy)
		aX = sX + active*dx
		aY = sY + active*dy

		d = Math.sqrt(Math.pow(aX - sX, 2) + Math.pow(aY - sY, 2))
		vX = (aX - sX) * aSize / d,
        vY = (aY - sY) * aSize / d;
		// console.log(aX, aY)

		context.strokeStyle = settings('edgeActiveColor') === 'edge'
		? (color || defaultEdgeColor)
		: settings('defaultEdgeActiveColor');
		context.lineWidth = size + 2
		context.beginPath();
		context.moveTo(sX, sY);
		context.lineTo(aX, aY);
		context.stroke();

		context.fillStyle = color;
		context.beginPath();
		context.moveTo(aX + vX, aY + vY);
		context.lineTo(aX + vY * 0.6, aY - vX * 0.6);
		context.lineTo(aX - vY * 0.6, aY + vX * 0.6);
		context.lineTo(aX + vX, aY + vY);
		context.closePath();
		context.fill();

		context.restore()

		// const slope = (y2 - y1) / (x2 - x1);
		// const intercept = y1 - slope * x1;
		// aX = x1 + (x2 - x1) * active
		// aY = aX * slope + intercept
		// console.log({ source, target, aX, aY, slope, intercept, x1,y1,x2,y2, active })
	}
  };
})();

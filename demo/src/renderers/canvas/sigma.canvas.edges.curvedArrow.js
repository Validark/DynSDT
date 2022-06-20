;(function() {
  'use strict';

  sigma.utils.pkg('sigma.canvas.edges');

  /**
   * This edge renderer will display edges as curves with arrow heading.
   *
   * @param  {object}                   edge         The edge object.
   * @param  {object}                   source node  The edge source node.
   * @param  {object}                   target node  The edge target node.
   * @param  {CanvasRenderingContext2D} context      The canvas context.
   * @param  {configurable}             settings     The settings function.
   */
  sigma.canvas.edges.curvedArrow =
    function(edge, source, target, context, settings) {
    var color = edge.color,
        prefix = settings('prefix') || '',
        edgeColor = settings('edgeColor'),
        defaultNodeColor = settings('defaultNodeColor'),
        defaultEdgeColor = settings('defaultEdgeColor'),
        cp = {},
        size = edge[prefix + 'size'] || 1,
        tSize = target[prefix + 'size'],
        sX = source[prefix + 'x'],
        sY = source[prefix + 'y'],
        tX = target[prefix + 'x'],
        tY = target[prefix + 'y'],
        aSize = Math.max(size * 2.5, settings('minArrowSize')),
        d,
        aX,
        aY,
        vX,
        vY;


		// console.log(target, prefix)
    cp = (source.id === target.id) ?
      sigma.utils.getSelfLoopControlPoints(sX, sY, tSize) :
      (source.id !== "d_list of$"
	  	? sigma.utils.getQuadraticControlPoint3(sX, sY, tX, tY, target.y)
		: sigma.utils.getQuadraticControlPoint3(sX, sY, tX, tY, target.y));
    //   sigma.utils.getQuadraticControlPoint2(source.x, source.y, target.x, target.y);

    if (source.id === target.id) {
      d = Math.sqrt(Math.pow(tX - cp.x1, 2) + Math.pow(tY - cp.y1, 2));
      aX = cp.x1 + (tX - cp.x1) * (d - aSize - tSize) / d;
      aY = cp.y1 + (tY - cp.y1) * (d - aSize - tSize) / d;
      vX = (tX - cp.x1) * aSize / d;
      vY = (tY - cp.y1) * aSize / d;
    }
    else {
      d = Math.sqrt(Math.pow(tX - cp.x, 2) + Math.pow(tY - cp.y, 2));
      aX = cp.x + (tX - cp.x) * (d - aSize - tSize) / d;
      aY = cp.y + (tY - cp.y) * (d - aSize - tSize) / d;
      vX = (tX - cp.x) * aSize / d;
      vY = (tY - cp.y) * aSize / d;
    }

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

    context.strokeStyle = color;
    context.lineWidth = size;
    context.beginPath();
    context.moveTo(sX, sY);
    if (source.id === target.id) {
      context.bezierCurveTo(cp.x2, cp.y2, cp.x1, cp.y1, aX, aY);
    } else {
    //   context.quadraticCurveTo(cp.x, cp.y, aX, aY);
      context.quadraticCurveTo(cp.x, cp.y, aX, aY);
	//   const b = cp.y + (aY - cp.y)
	//   const radius = 20
	//   context.moveTo(cp.x + radius, b);
	//   context.quadraticCurveTo(cp.x, b, cp.x, b - radius);

// 	  function roundedRectangle(x, y, w, h)
// {
//   var canvas = document.getElementById("canvas4");
//   var context = canvas.getContext("2d");
//   var mx = x + w / 2;
//   var my = y + h / 2;
//   context.beginPath();
//   context.strokeStyle="green";
//   context.lineWidth="4";
//   context.moveTo(x,my);
//   context.quadraticCurveTo(x, y, mx, y);
//   context.quadraticCurveTo(x+w, y, x+w, my);
//   context.quadraticCurveTo(x+w, y+h, mx, y+h);
//   context.quadraticCurveTo(x, y+h, x, my);
//   context.stroke();
// }
// roundedRectangle(10, 10, 200, 100);
    }
    context.stroke();

    context.fillStyle = color;
    context.beginPath();
    context.moveTo(aX + vX, aY + vY);
    context.lineTo(aX + vY * 0.6, aY - vX * 0.6);
    context.lineTo(aX - vY * 0.6, aY + vX * 0.6);
    context.lineTo(aX + vX, aY + vY);
    context.closePath();
    context.fill();
  };
})();

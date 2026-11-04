## Screen scale + safe areas. Keeps one UI unit close to one CSS pixel on
## phones (so a 48-unit button is >= 48 CSS px), lets big screens use the
## extra space instead of growing without limit, and reports the notch /
## gesture-bar insets in UI units.
extends RefCounted

const PORTRAIT_MIN := Vector2(360, 600)  # smallest UI area we design for
const LANDSCAPE_MIN := Vector2(640, 400)
const MAX_SCALE := 1.5  # CSS px per UI unit on large screens

const SAFE_AREA_JS := """
(function () {
	var d = document.createElement('div');
	d.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;pointer-events:none;' +
		'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);';
	document.body.appendChild(d);
	var s = getComputedStyle(d);
	var out = [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].map(parseFloat);
	d.remove();
	out.push(window.devicePixelRatio || 1);
	return out.join(',');
})();
"""


## Returns {"dpr": device px per CSS px, "insets": [top, right, bottom, left] in CSS px}.
static func css_info() -> Dictionary:
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval(SAFE_AREA_JS, true)
		if typeof(raw) == TYPE_STRING:
			var p: PackedStringArray = raw.split(",")
			if p.size() == 5:
				return {"dpr": maxf(0.5, p[4].to_float()), "insets": [p[0].to_float(), p[1].to_float(), p[2].to_float(), p[3].to_float()]}
		return {"dpr": 1.0, "insets": [0.0, 0.0, 0.0, 0.0]}
	var dpr := maxf(1.0, DisplayServer.screen_get_scale())
	var insets := [0.0, 0.0, 0.0, 0.0]
	if OS.has_feature("mobile"):
		var win := DisplayServer.window_get_size()
		var safe := DisplayServer.get_display_safe_area()
		insets = [safe.position.y / dpr, (win.x - safe.end.x) / dpr, (win.y - safe.end.y) / dpr, safe.position.x / dpr]
	return {"dpr": dpr, "insets": insets}


## Sets the window's content scale and returns {"size": UI size, "insets": [t, r, b, l] in UI units}.
static func apply(window: Window) -> Dictionary:
	var info := css_info()
	var dpr: float = info["dpr"]
	var css := Vector2(window.size) / dpr
	var min_area := PORTRAIT_MIN if css.x < css.y else LANDSCAPE_MIN
	var s := minf(MAX_SCALE, minf(css.x / min_area.x, css.y / min_area.y))
	s = maxf(s, 0.25)
	var ui := Vector2i(maxi(1, roundi(css.x / s)), maxi(1, roundi(css.y / s)))
	if window.content_scale_size != ui:
		window.content_scale_size = ui
	var insets: Array = info["insets"].map(func(v): return v / s)
	return {"size": Vector2(ui), "insets": insets, "css_per_unit": s}

package lime._internal.backend.html5;

import haxe.Timer;
import js.html.webgl.RenderingContext;
import js.html.CanvasElement;
import js.html.DivElement;
import js.html.DragEvent;
import js.html.Element;
import js.html.FocusEvent;
import js.html.InputElement;
import js.html.InputEvent;
import js.html.LinkElement;
import js.html.MouseEvent;
import js.html.Node;
import js.html.TextAreaElement;
import js.html.TouchEvent;
import js.html.ClipboardEvent;
import js.Browser;
import lime._internal.graphics.ImageCanvasUtil;
import lime.app.Application;
import lime.graphics.opengl.GL;
import lime.graphics.Image;
import lime.graphics.OpenGLRenderContext;
import lime.graphics.RenderContext;
import lime.graphics.RenderContextType;
import lime.math.Rectangle;
import lime.system.Display;
import lime.system.DisplayMode;
import lime.system.System;
import lime.system.Clipboard;
import lime.ui.Gamepad;
import lime.ui.Joystick;
import lime.ui.MouseCursor;
import lime.ui.MouseWheelMode;
import lime.ui.Touch;
import lime.ui.Window;

@:access(lime._internal.backend.html5.HTML5Application)
@:access(lime._internal.backend.html5.HTML5WebGL2RenderContext)
@:access(lime.app.Application)
@:access(lime.graphics.opengl.GL)
@:access(lime.graphics.OpenGLRenderContext)
@:access(lime.graphics.RenderContext)
@:access(lime.ui.Gamepad)
@:access(lime.ui.Joystick)
@:access(lime.ui.Window)
class HTML5Window
{
	private static var dummyCharacter = String.fromCharCode(127);
	private static var textArea:TextAreaElement;
	private static var textInput:InputElement;
	private static var windowID:Int = 0;

	public var canvas:CanvasElement;
	public var div:DivElement;
	#if stats
	public var stats:Dynamic;
	#end

	private var cacheElementHeight:Float;
	private var cacheElementWidth:Float;
	private var cacheMouseX:Float;
	private var cacheMouseY:Float;
	private var cursor:MouseCursor;
	private var currentTouches = new Map<Int, Touch>();
	private var isFullscreen:Bool;
	private var parent:Window;
	private var primaryTouch:Touch;
	private var renderType:RenderContextType;
	private var requestedFullscreen:Bool;
	private var resizeElement:Bool;
	private var scale = 1.0;
	private var setHeight:Int;
	private var setWidth:Int;
	private var textInputEnabled:Bool;
	private var unusedTouchesPool = new List<Touch>();

	public function new(parent:Window)
	{
		this.parent = parent;

		cursor = DEFAULT;
		cacheMouseX = 0;
		cacheMouseY = 0;

		var attributes = parent.__attributes;
		if (!Reflect.hasField(attributes, "context")) attributes.context = {};

		#if dom
		attributes.context.type = DOM;
		attributes.context.version = "";
		#end

		renderType = attributes.context.type;

		if (Reflect.hasField(attributes, "element"))
		{
			parent.element = attributes.element;
		}

		var element = parent.element;

		if (Reflect.hasField(attributes, "allowHighDPI") && attributes.allowHighDPI && renderType != DOM)
		{
			scale = Browser.window.devicePixelRatio;
		}

		parent.__scale = scale;

		setWidth = Reflect.hasField(attributes, "width") ? attributes.width : 0;
		setHeight = Reflect.hasField(attributes, "height") ? attributes.height : 0;
		parent.__width = setWidth;
		parent.__height = setHeight;

		parent.id = windowID++;

		if ((element is CanvasElement))
		{
			canvas = cast element;
		}
		else
		{
			if (renderType == DOM)
			{
				div = cast Browser.document.createElement("div");
			}
			else
			{
				canvas = cast Browser.document.createElement("canvas");
			}
		}

		if (canvas != null)
		{
			var style = canvas.style;
			style.setProperty("-webkit-transform", "translateZ(0)", null);
			style.setProperty("transform", "translateZ(0)", null);
		}
		else if (div != null)
		{
			var style = div.style;
			style.setProperty("-webkit-transform", "translate3D(0,0,0)", null);
			style.setProperty("transform", "translate3D(0,0,0)", null);
			// style.setProperty ("-webkit-transform-style", "preserve-3d", null);
			// style.setProperty ("transform-style", "preserve-3d", null);
			style.position = "relative";
			style.overflow = "hidden";
			style.setProperty("-webkit-user-select", "none", null);
			style.setProperty("-moz-user-select", "none", null);
			style.setProperty("-ms-user-select", "none", null);
			style.setProperty("-o-user-select", "none", null);
		}

		if (parent.__width == 0 && parent.__height == 0)
		{
			if (element != null)
			{
				parent.__width = element.clientWidth;
				parent.__height = element.clientHeight;
			}
			else
			{
				parent.__width = Browser.window.innerWidth;
				parent.__height = Browser.window.innerHeight;
			}

			cacheElementWidth = parent.__width;
			cacheElementHeight = parent.__height;

			resizeElement = true;
		}

		if (canvas != null)
		{
			canvas.width = Math.round(parent.__width * scale);
			canvas.height = Math.round(parent.__height * scale);

			canvas.style.width = parent.__width + "px";
			canvas.style.height = parent.__height + "px";
		}
		else
		{
			div.style.width = parent.__width + "px";
			div.style.height = parent.__height + "px";
		}

		if ((Reflect.hasField(attributes, "resizable") && attributes.resizable)
			|| (!Reflect.hasField(attributes, "width") && setWidth == 0 && setHeight == 0))
		{
			parent.__resizable = true;
		}

		updateSize();

		if (element != null)
		{
			if (canvas != null)
			{
				if (element != cast canvas)
				{
					element.appendChild(canvas);
				}
			}
			else
			{
				element.appendChild(div);
			}

			var events = ["mousedown", "mouseenter", "mouseleave", "mousemove", "mouseup", "wheel"];

			for (event in events)
			{
				element.addEventListener(event, handleMouseEvent, true);
			}

			element.addEventListener("contextmenu", handleContextMenuEvent, true);

			element.addEventListener("dragstart", handleDragEvent, true);
			element.addEventListener("dragover", handleDragEvent, true);
			element.addEventListener("drop", handleDragEvent, true);

			element.addEventListener("touchstart", handleTouchEvent, true);
			element.addEventListener("touchmove", handleTouchEvent, true);
			element.addEventListener("touchend", handleTouchEvent, true);
			element.addEventListener("touchcancel", handleTouchEvent, true);

			element.addEventListener("gamepadconnected", handleGamepadEvent, true);
			element.addEventListener("gamepaddisconnected", handleGamepadEvent, true);
		}

		createContext();

		if (parent.context.type == WEBGL)
		{
			canvas.addEventListener("webglcontextlost", handleContextEvent, false);
			canvas.addEventListener("webglcontextrestored", handleContextEvent, false);
		}
	}

	public function alert(message:String, title:String):Void
	{
		if (message != null)
		{
			Browser.alert(message);
		}
	}

	public function close():Void
	{
		parent.application.__removeWindow(parent);
	}

	private function createContext():Void
	{
		var context = new RenderContext();
		var contextAttributes = parent.__attributes.context;

		context.window = parent;
		context.attributes = contextAttributes;

		if (div != null)
		{
			context.dom = cast div;
			context.type = DOM;
			context.version = "";
		}
		else if (canvas != null)
		{
			var webgl:#if !doc_gen HTML5WebGL2RenderContext #else Dynamic #end = null;

			var forceCanvas = #if (canvas || munit) true #else (renderType == CANVAS) #end;
			var forceWebGL = #if webgl true #else (renderType == OPENGL || renderType == OPENGLES || renderType == WEBGL) #end;
			var allowWebGL2 = #if webgl1 false #else (!Reflect.hasField(contextAttributes, "version")
				|| contextAttributes.version != "1") #end;
			var isWebGL2 = false;

			if (forceWebGL || (!forceCanvas && (!Reflect.hasField(contextAttributes, "hardware") || contextAttributes.hardware)))
			{
				var transparentBackground = Reflect.hasField(contextAttributes, "background") && contextAttributes.background == null;
				var colorDepth = Reflect.hasField(contextAttributes, "colorDepth") ? contextAttributes.colorDepth : 16;

				var options =
					{
						alpha: (transparentBackground || colorDepth > 16) ? true : false,
						antialias: Reflect.hasField(contextAttributes, "antialiasing") ? contextAttributes.antialiasing > 0 : false,
						depth: Reflect.hasField(contextAttributes, "depth") ? contextAttributes.depth : true,
						premultipliedAlpha: true,
						stencil: Reflect.hasField(contextAttributes, "stencil") ? contextAttributes.stencil : false,
						preserveDrawingBuffer: false,
						failIfMajorPerformanceCaveat: false
					};

				var glContextType = ["webgl", "experimental-webgl"];

				if (allowWebGL2)
				{
					glContextType.unshift("webgl2");
				}

				for (name in glContextType)
				{
					webgl = cast canvas.getContext(name, options);
					if (webgl != null && name == "webgl2") isWebGL2 = true;
					if (webgl != null) break;
				}
			}

			if (webgl == null)
			{
				context.canvas2D = cast canvas.getContext("2d");
				context.type = CANVAS;
				context.version = "";
			}
			else
			{
				#if webgl_debug
				webgl = untyped WebGLDebugUtils.makeDebugContext(webgl);
				#end

				#if (js && html5)
				context.webgl = webgl;
				if (isWebGL2) context.webgl2 = webgl;

				if (GL.context == null)
				{
					GL.context = cast webgl;
					GL.type = WEBGL;
					GL.version = isWebGL2 ? 2 : 1;
				}
				#end

				context.type = WEBGL;
				context.version = isWebGL2 ? "2" : "1";
			}
		}

		parent.context = context;
	}

	public function focus():Void {}

	public function getCursor():MouseCursor
	{
		return cursor;
	}

	public function getDisplay():Display
	{
		return System.getDisplay(0);
	}

	public function getDisplayMode():DisplayMode
	{
		return System.getDisplay(0).currentMode;
	}

	public function getFrameRate():Float
	{
		if (parent.application == null) return 0;

		if (parent.application.__backend.framePeriod < 0)
		{
			return 60;
		}
		else if (parent.application.__backend.framePeriod == 1000)
		{
			return 0;
		}
		else
		{
			return 1000 / parent.application.__backend.framePeriod;
		}
	}

	public function getMouseLock():Bool
	{
		return false;
	}

	public function getTextInputEnabled():Bool
	{
		return textInputEnabled;
	}

	private function handleContextEvent(event:js.html.Event):Void
	{
		switch (event.type)
		{
			case "webglcontextlost":
				if (event.cancelable) event.preventDefault();

				// #if !display
				if (GL.context != null)
				{
					// GL.context.__contextLost = true;
				}
				// #end

				parent.context = null;

				parent.onRenderContextLost.dispatch();

			case "webglcontextrestored":
				createContext();

				parent.onRenderContextRestored.dispatch(parent.context);

			default:
		}
	}

	private function handleContextMenuEvent(event:MouseEvent):Void
	{
		if ((parent.onMouseUp.canceled || parent.onMouseDown.canceled) && event.cancelable)
		{
			event.preventDefault();
		}
	}

	private function handleCutOrCopyEvent(event:ClipboardEvent):Void
	{
		event.clipboardData.setData("text/plain", Clipboard.text);
		if (event.cancelable) event.preventDefault();
	}

	private function handleDragEvent(event:DragEvent):Bool
	{
		switch (event.type)
		{
			case "dragstart":
				if (cast(event.target, Element).nodeName.toLowerCase() == "img" && event.cancelable)
				{
					event.preventDefault();
					return false;
				}

			case "dragover":
				event.preventDefault();
				return false;

			case "drop":
				// TODO: Create a formal API that supports HTML5 file objects
				if (event.dataTransfer != null && event.dataTransfer.files.length > 0)
				{
					parent.onDropFile.dispatch(cast event.dataTransfer.files);
					event.preventDefault();
					return false;
				}
		}

		return true;
	}

	private function handleFocusEvent(event:FocusEvent):Void
	{
		if (textInputEnabled)
		{
			if (event.relatedTarget == null || isDescendent(cast event.relatedTarget))
			{
				Timer.delay(function()
				{
					if (textInputEnabled) textInput.focus();
				}, 20);
			}
		}
	}

	private function handleFullscreenEvent(event:Dynamic):Void
	{
		var fullscreenElement = untyped (document.fullscreenElement || document.mozFullScreenElement || document.webkitFullscreenElement
			|| document.msFullscreenElement);

		if (fullscreenElement != null)
		{
			isFullscreen = true;
			parent.__fullscreen = true;

			if (requestedFullscreen)
			{
				requestedFullscreen = false;
				parent.onFullscreen.dispatch();
			}
		}
		else
		{
			isFullscreen = false;
			parent.__fullscreen = false;

			// TODO: Handle a different way?
			parent.onRestore.dispatch();
			// parent.onResize.dispatch (parent.__width, parent.__height);

			var changeEvents = [
				"fullscreenchange",
				"mozfullscreenchange",
				"webkitfullscreenchange",
				"MSFullscreenChange"
			];
			var errorEvents = [
				"fullscreenerror",
				"mozfullscreenerror",
				"webkitfullscreenerror",
				"MSFullscreenError"
			];

			for (i in 0...changeEvents.length)
			{
				Browser.document.removeEventListener(changeEvents[i], handleFullscreenEvent, false);
				Browser.document.removeEventListener(errorEvents[i], handleFullscreenEvent, false);
			}
		}
	}

	private function handleGamepadEvent(event:Dynamic):Void
	{
		switch (event.type)
		{
			case "gamepadconnected":
				Joystick.__connect(event.gamepad.index);

				if (event.gamepad.mapping == "standard")
				{
					Gamepad.__connect(event.gamepad.index);
				}

			case "gamepaddisconnected":
				Joystick.__disconnect(event.gamepad.index);
				Gamepad.__disconnect(event.gamepad.index);

			default:
		}
	}

	private function handleInputEvent(event:InputEvent):Void
	{
		// In order to ensure that the browser will fire clipboard events, we always need to have something selected.
		// Therefore, `value` cannot be "".

		if (inputing) return;

		if (textInput.value != dummyCharacter)
		{
			var value = StringTools.replace(textInput.value, dummyCharacter, "");

			if (value.length > 0)
			{
				parent.onTextInput.dispatch(value);
			}

			textInput.value = dummyCharacter;
		}
	}

	private function handleMouseEvent(event:MouseEvent):Void
	{
		var x = 0.0;
		var y = 0.0;

		if (event.type != "wheel")
		{
			if (parent.element != null)
			{
				if (canvas != null)
				{
					var rect = canvas.getBoundingClientRect();
					x = (event.clientX - rect.left) * (parent.__width / rect.width);
					y = (event.clientY - rect.top) * (parent.__height / rect.height);
				}
				else if (div != null)
				{
					var rect = div.getBoundingClientRect();
					// x = (event.clientX - rect.left) * (window.__backend.div.style.width / rect.width);
					x = (event.clientX - rect.left);
					// y = (event.clientY - rect.top) * (window.__backend.div.style.height / rect.height);
					y = (event.clientY - rect.top);
				}
				else
				{
					var rect = parent.element.getBoundingClientRect();
					x = (event.clientX - rect.left) * (parent.__width / rect.width);
					y = (event.clientY - rect.top) * (parent.__height / rect.height);
				}
			}
			else
			{
				x = event.clientX;
				y = event.clientY;
			}

			switch (event.type)
			{
				case "mousedown":
					if (event.currentTarget == parent.element)
					{
						// Release outside browser window
						Browser.window.addEventListener("mouseup", handleMouseEvent);
					}

					parent.onMouseDown.dispatch(x, y, event.button);

					if (parent.onMouseDown.canceled && event.cancelable)
					{
						event.preventDefault();
					}

				case "mouseenter":
					if (event.target == parent.element)
					{
						parent.onEnter.dispatch();

						if (parent.onEnter.canceled && event.cancelable)
						{
							event.preventDefault();
						}
					}

				case "mouseleave":
					if (event.target == parent.element)
					{
						parent.onLeave.dispatch();

						if (parent.onLeave.canceled && event.cancelable)
						{
							event.preventDefault();
						}
					}

				case "mouseup":
					Browser.window.removeEventListener("mouseup", handleMouseEvent);

					if (event.currentTarget == parent.element)
					{
						event.stopPropagation();
					}

					parent.onMouseUp.dispatch(x, y, event.button);

					if (parent.onMouseUp.canceled && event.cancelable)
					{
						event.preventDefault();
					}

				case "mousemove":
					if (x != cacheMouseX || y != cacheMouseY)
					{
						parent.onMouseMove.dispatch(x, y);
						parent.onMouseMoveRelative.dispatch(x - cacheMouseX, y - cacheMouseY);

						if ((parent.onMouseMove.canceled || parent.onMouseMoveRelative.canceled) && event.cancelable)
						{
							event.preventDefault();
						}
					}

				default:
			}

			cacheMouseX = x;
			cacheMouseY = y;
		}
		else
		{
			var deltaMode:MouseWheelMode = switch (untyped event.deltaMode)
			{
				case 0: PIXELS;
				case 1: LINES;
				case 2: PAGES;
				default: UNKNOWN;
			}

			parent.onMouseWheel.dispatch(untyped event.deltaX, -untyped event.deltaY, deltaMode);

			if (parent.onMouseWheel.canceled && event.cancelable)
			{
				event.preventDefault();
			}
		}
	}

	private function handlePasteEvent(event:ClipboardEvent):Void
	{
		if (untyped event.clipboardData.types.indexOf("text/plain") > -1)
		{
			var text = event.clipboardData.getData("text/plain");
			Clipboard.text = text;

			if (textInputEnabled)
			{
				parent.onTextInput.dispatch(text);
			}

			if (event.cancelable) event.preventDefault();
		}
	}

	private function handleResizeEvent(event:js.html.Event):Void
	{
		primaryTouch = null;
		updateSize();
	}

	private function handleTouchEvent(event:TouchEvent):Void
	{
		if (event.cancelable) event.preventDefault();

		var rect = null;

		if (parent.element != null)
		{
			if (canvas != null)
			{
				rect = canvas.getBoundingClientRect();
			}
			else if (div != null)
			{
				rect = div.getBoundingClientRect();
			}
			else
			{
				rect = parent.element.getBoundingClientRect();
			}
		}

		var windowWidth:Float = setWidth;
		var windowHeight:Float = setHeight;

		if (windowWidth == 0 || windowHeight == 0)
		{
			if (rect != null)
			{
				windowWidth = rect.width;
				windowHeight = rect.height;
			}
			else
			{
				windowWidth = 1;
				windowHeight = 1;
			}
		}

		var touch, x, y, cacheX, cacheY;

		for (data in event.changedTouches)
		{
			x = 0.0;
			y = 0.0;

			if (rect != null)
			{
				x = (data.clientX - rect.left) * (windowWidth / rect.width);
				y = (data.clientY - rect.top) * (windowHeight / rect.height);
			}
			else
			{
				x = data.clientX;
				y = data.clientY;
			}

			if (event.type == "touchstart")
			{
				touch = unusedTouchesPool.pop();

				if (touch == null)
				{
					touch = new Touch(x / windowWidth, y / windowHeight, data.identifier, 0, 0, data.force, parent.id);
				}
				else
				{
					touch.x = x / windowWidth;
					touch.y = y / windowHeight;
					touch.id = data.identifier;
					touch.dx = 0;
					touch.dy = 0;
					touch.pressure = data.force;
					touch.device = parent.id;
				}

				currentTouches.set(data.identifier, touch);

				Touch.onStart.dispatch(touch);

				if (primaryTouch == null)
				{
					primaryTouch = touch;
				}

				if (touch == primaryTouch)
				{
					parent.onMouseDown.dispatch(x, y, 0);
				}
			}
			else
			{
				touch = currentTouches.get(data.identifier);

				if (touch != null)
				{
					cacheX = touch.x;
					cacheY = touch.y;

					touch.x = x / windowWidth;
					touch.y = y / windowHeight;
					touch.dx = touch.x - cacheX;
					touch.dy = touch.y - cacheY;
					touch.pressure = data.force;

					switch (event.type)
					{
						case "touchmove":
							Touch.onMove.dispatch(touch);

							if (touch == primaryTouch)
							{
								parent.onMouseMove.dispatch(x, y);
							}

						case "touchend":
							Touch.onEnd.dispatch(touch);

							currentTouches.remove(data.identifier);
							unusedTouchesPool.add(touch);

							if (touch == primaryTouch)
							{
								parent.onMouseUp.dispatch(x, y, 0);
								primaryTouch = null;
							}

						case "touchcancel":
							Touch.onCancel.dispatch(touch);

							currentTouches.remove(data.identifier);
							unusedTouchesPool.add(touch);

							if (touch == primaryTouch)
							{
								// parent.onMouseUp.dispatch (x, y, 0);
								primaryTouch = null;
							}

						default:
					}
				}
			}
		}
	}

	private function isDescendent(node:Node):Bool
	{
		if (node == parent.element) return true;

		while (node != null)
		{
			if (node.parentNode == parent.element)
			{
				return true;
			}

			node = node.parentNode;
		}

		return false;
	}

	public function move(x:Int, y:Int):Void {}

	public function readPixels(rect:Rectangle):Image
	{
		// TODO: Handle DIV, improve 3D canvas support

		if (canvas != null)
		{
			var stageRect = new Rectangle(0, 0, canvas.width, canvas.height);

			if (rect == null)
			{
				rect = stageRect;
			}
			else
			{
				rect.intersection(stageRect, rect);
			}

			if (rect.width > 0 && rect.height > 0)
			{
				var canvas2:CanvasElement = cast Browser.document.createElement("canvas");
				canvas2.width = Std.int(rect.width);
				canvas2.height = Std.int(rect.height);

				var context = canvas2.getContext("2d");
				context.drawImage(canvas, -rect.x, -rect.y);

				return Image.fromCanvas(canvas2);
			}
		}

		return null;
	}

	public function resize(width:Int, height:Int):Void {}

	public function setBorderless(value:Bool):Bool
	{
		return value;
	}

	public function setClipboard(value:String):Void
	{
		if (textArea == null)
		{
			textArea = cast Browser.document.createElement("textarea");
			textArea.style.height = "0px";
			textArea.style.left = "-100px";
			textArea.style.opacity = "0";
			textArea.style.position = "fixed";
			textArea.style.top = "-100px";
			textArea.style.width = "0px";
			Browser.document.body.appendChild(textArea);
		}
		textArea.value = value;
		textArea.focus();
		textArea.select();

		if (Browser.document.queryCommandEnabled("copy"))
		{
			Browser.document.execCommand("copy");
		}
	}

	public function setCursor(value:MouseCursor):MouseCursor
	{
		if (cursor != value)
		{
			if (value == null)
			{
				parent.element.style.cursor = "none";
			}
			else
			{
				parent.element.style.cursor = switch (value)
				{
					case ARROW: "default";
					case CROSSHAIR: "crosshair";
					case MOVE: "move";
					case POINTER: "pointer";
					case RESIZE_NESW: "nesw-resize";
					case RESIZE_NS: "ns-resize";
					case RESIZE_NWSE: "nwse-resize";
					case RESIZE_WE: "ew-resize";
					case TEXT: "text";
					case WAIT: "wait";
					case WAIT_ARROW: "wait";
					default: "auto";
				}
			}

			cursor = value;
		}

		return cursor;
	}

	public function setDisplayMode(value:DisplayMode):DisplayMode
	{
		return value;
	}

	public function setFrameRate(value:Float):Float
	{
		if (parent.application != null)
		{
			if (value >= 60)
			{
				if (parent == parent.application.window) parent.application.__backend.framePeriod = -1;
			}
			else if (value > 0)
			{
				if (parent == parent.application.window) parent.application.__backend.framePeriod = 1000 / value;
			}
			else
			{
				if (parent == parent.application.window) parent.application.__backend.framePeriod = 1000;
			}
		}

		return value;
	}

	public function setFullscreen(value:Bool):Bool
	{
		if (value)
		{
			if (!requestedFullscreen && !isFullscreen)
			{
				requestedFullscreen = true;

				untyped
				{
					if (parent.element.requestFullscreen)
					{
						document.addEventListener("fullscreenchange", handleFullscreenEvent, false);
						document.addEventListener("fullscreenerror", handleFullscreenEvent, false);
						parent.element.requestFullscreen();
					}
					else if (parent.element.mozRequestFullScreen)
					{
						document.addEventListener("mozfullscreenchange", handleFullscreenEvent, false);
						document.addEventListener("mozfullscreenerror", handleFullscreenEvent, false);
						parent.element.mozRequestFullScreen();
					}
					else if (parent.element.webkitRequestFullscreen)
					{
						document.addEventListener("webkitfullscreenchange", handleFullscreenEvent, false);
						document.addEventListener("webkitfullscreenerror", handleFullscreenEvent, false);
						parent.element.webkitRequestFullscreen();
					}
					else if (parent.element.msRequestFullscreen)
					{
						document.addEventListener("MSFullscreenChange", handleFullscreenEvent, false);
						document.addEventListener("MSFullscreenError", handleFullscreenEvent, false);
						parent.element.msRequestFullscreen();
					}
				}
			}
		}
		else if (isFullscreen)
		{
			requestedFullscreen = false;

			untyped
			{
				if (document.exitFullscreen) document.exitFullscreen();
				else if (document.mozCancelFullScreen) document.mozCancelFullScreen();
				else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
				else if (document.msExitFullscreen) document.msExitFullscreen();
			}
		}

		return value;
	}

	public function setIcon(image:Image):Void
	{
		// var iconWidth = 16;
		// var iconHeight = 16;

		// image = image.clone ();

		// if (image.width != iconWidth || image.height != iconHeight) {
		//
		// image.resize (iconWidth, iconHeight);
		//
		// }

		ImageCanvasUtil.convertToCanvas(image);

		var link:LinkElement = cast Browser.document.querySelector("link[rel*='icon']");

		if (link == null)
		{
			link = cast Browser.document.createElement("link");
		}

		link.type = "image/x-icon";
		link.rel = "shortcut icon";
		link.href = image.buffer.src.toDataURL("image/x-icon");

		Browser.document.getElementsByTagName("head")[0].appendChild(link);
	}

	public function setMaximized(value:Bool):Bool
	{
		return false;
	}

	public function setMinimized(value:Bool):Bool
	{
		return false;
	}

	public function setMouseLock(value:Bool):Void {}

	public function setResizable(value:Bool):Bool
	{
		return value;
	}

	public function setTextInputEnabled(value:Bool):Bool
	{
		if (value)
		{
			if (textInput == null)
			{
				textInput = cast Browser.document.createElement('input');
				textInput.type = 'text';
				textInput.style.position = 'absolute';
				textInput.style.opacity = "0";
				textInput.style.color = "transparent";
				textInput.value = dummyCharacter; // See: handleInputEvent()

				untyped textInput.autocapitalize = "off";
				untyped textInput.autocorrect = "off";
				textInput.autocomplete = "off";

				// TODO: Position for mobile browsers better

				textInput.style.left = "0px";
				textInput.style.top = "50%";

				if (~/(iPad|iPhone|iPod).*OS 8_/gi.match(Browser.window.navigator.userAgent))
				{
					textInput.style.fontSize = "0px";
					textInput.style.width = '0px';
					textInput.style.height = '0px';
				}
				else
				{
					textInput.style.width = '1px';
					textInput.style.height = '1px';
				}

				untyped (textInput.style).pointerEvents = 'none';
				textInput.style.zIndex = "-10000000";
			}

			if (textInput.parentNode == null)
			{
				parent.element.appendChild(textInput);
			}

			if (!textInputEnabled)
			{
				textInput.addEventListener('input', handleInputEvent, true);
				textInput.addEventListener('blur', handleFocusEvent, true);
				textInput.addEventListener('cut', handleCutOrCopyEvent, true);
				textInput.addEventListener('copy', handleCutOrCopyEvent, true);
				textInput.addEventListener('paste', handlePasteEvent, true);
				textInput.addEventListener('compositionstart', handleCompositionstartEvent, true);
				textInput.addEventListener('compositionend', handleCompositionendEvent, true);
			}

			textInput.focus();
			textInput.select();
		}
		else
		{
			if (textInput != null)
			{
				textInput.removeEventListener('input', handleInputEvent, true);
				textInput.removeEventListener('blur', handleFocusEvent, true);
				textInput.removeEventListener('cut', handleCutOrCopyEvent, true);
				textInput.removeEventListener('copy', handleCutOrCopyEvent, true);
				textInput.removeEventListener('paste', handlePasteEvent, true);
				textInput.removeEventListener('compositionstart', handleCompositionstartEvent, true);
				textInput.removeEventListener('compositionend', handleCompositionendEvent, true);

				textInput.blur();
			}
		}

		return textInputEnabled = value;
	}

	private var inputing = false;

	public function handleCompositionstartEvent(e):Void
	{
		inputing = true;
	}

	public function handleCompositionendEvent(e):Void
	{
		inputing = false;
		handleInputEvent(e);
	}

	public function setTitle(value:String):String
	{
		if (value != null)
		{
			Browser.document.title = value;
		}

		return value;
	}

	private function updateSize():Void
	{
		if (!parent.__resizable) return;

		var elementWidth, elementHeight;

		if (parent.element != null)
		{
			elementWidth = parent.element.clientWidth;
			elementHeight = parent.element.clientHeight;
		}
		else
		{
			elementWidth = Browser.window.innerWidth;
			elementHeight = Browser.window.innerHeight;
		}

		if (elementWidth != cacheElementWidth || elementHeight != cacheElementHeight)
		{
			cacheElementWidth = elementWidth;
			cacheElementHeight = elementHeight;

			var stretch = resizeElement || (setWidth == 0 && setHeight == 0);

			if (parent.element != null && (div == null || (div != null && stretch)))
			{
				if (stretch)
				{
					if (parent.__width != elementWidth || parent.__height != elementHeight)
					{
						parent.__width = elementWidth;
						parent.__height = elementHeight;

						if (canvas != null)
						{
							if (parent.element != cast canvas)
							{
								canvas.width = Math.round(elementWidth * scale);
								canvas.height = Math.round(elementHeight * scale);

								canvas.style.width = elementWidth + "px";
								canvas.style.height = elementHeight + "px";
							}
						}
						else
						{
							div.style.width = elementWidth + "px";
							div.style.height = elementHeight + "px";
						}

						parent.onResize.dispatch(elementWidth, elementHeight);
					}
				}
				else
				{
					var scaleX = (setWidth != 0) ? (elementWidth / setWidth) : 1;
					var scaleY = (setHeight != 0) ? (elementHeight / setHeight) : 1;

					var targetWidth = elementWidth;
					var targetHeight = elementHeight;
					var marginLeft = 0;
					var marginTop = 0;

					if (scaleX < scaleY)
					{
						targetHeight = Math.floor(setHeight * scaleX);
						marginTop = Math.floor((elementHeight - targetHeight) / 2);
					}
					else
					{
						targetWidth = Math.floor(setWidth * scaleY);
						marginLeft = Math.floor((elementWidth - targetWidth) / 2);
					}

					if (canvas != null)
					{
						if (parent.element != cast canvas)
						{
							canvas.style.width = targetWidth + "px";
							canvas.style.height = targetHeight + "px";
							canvas.style.marginLeft = marginLeft + "px";
							canvas.style.marginTop = marginTop + "px";
						}
					}
					else
					{
						div.style.width = targetWidth + "px";
						div.style.height = targetHeight + "px";
						div.style.marginLeft = marginLeft + "px";
						div.style.marginTop = marginTop + "px";
					}
				}
			}
		}
	}

	public function warpMouse(x:Int, y:Int):Void {}
}

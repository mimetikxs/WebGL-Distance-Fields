package;

import dat.GUI;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import js.Browser;
import msignal.Signal.Signal0;
import msignal.Signal.Signal1;
import shaders.EDT.EDT_DISPLAY_AA;
import stats.Stats;
import three.Color;
import three.ImageUtils;
import three.Mapping;
import three.Mesh;
import three.PerspectiveCamera;
import three.PlaneGeometry;
import three.postprocessing.EffectComposer;
import three.Scene;
import three.ShaderMaterial;
import three.Texture;
import three.WebGLRenderer;
import three.WebGLRenderTarget;
import webgl.Detector;
import shaders.FXAA;
import dat.ShaderGUI;
import dat.ThreeObjectGUI;
import shaders.EDT.EDT_DISPLAY_RGB;
import shaders.EDT.EDT_DISPLAY_OVERLAY;
import shaders.EDT.EDT_DISPLAY_ALPHA_THRESHOLD;
import composer.ShaderPass;
import composer.RenderPass;
import composer.CopyShader;
import shaders.Copy;

class Main {
	public static inline var REPO_URL:String = "https://github.com/Tw1ddle/WebGLDistanceFields";
	public static inline var WEBSITE_URL:String = "http://samcodes.co.uk/";
	public static inline var TWITTER_URL:String = "https://twitter.com/Sam_Twidale";
	public static inline var HAXE_URL:String = "http://haxe.org/";
	
	private var gameAttachPoint:Dynamic;
	
	private var composer:EffectComposer;
	private var renderer:WebGLRenderer;

	private var scene:Scene;
	private var camera:PerspectiveCamera;
	
	private var sdfMaker:SDFMaker;
	private var sdfMap:StringMap<WebGLRenderTarget> = new StringMap<WebGLRenderTarget>();
	
	private var aaMaterials = new Array<{ mesh:Mesh, material: ShaderMaterial, sdf: WebGLRenderTarget }>();
	private var rgbMaterials = new Array<{ mesh:Mesh, material: ShaderMaterial, sdf: WebGLRenderTarget }>();
	private var alphaThresholdMaterials = new Array<{ mesh:Mesh, material: ShaderMaterial, sdf: WebGLRenderTarget }>();
	private var overlayMaterials = new Array<{ mesh:Mesh, material: ShaderMaterial, sdf: WebGLRenderTarget }>();
	private var copyMaterials = new Array<{ mesh:Mesh, material: ShaderMaterial, sdf: WebGLRenderTarget }>();
	
	private var displayShader:String = "AA";
	private var displayShaders = [ "AA", "RGB", "ALPHA_THRESHOLD", "OVERLAY", "COPY" ];
	
	public var signal_letterTyped(default, null) = new Signal1<String>();
	public var signal_windowResized(default, null) = new Signal0();
	
	private static var lastAnimationTime:Float = 0.0; // Last time from requestAnimationFrame
	private static var dt:Float = 0.0; // Frame delta time
	
	private var sceneGUI:GUI = new GUI( { autoPlace:true } );
	private var shaderGUI:GUI = new GUI( { autoPlace:true } );
	
	#if debug
	public var stats(default, null):Stats;
	#end
	
    private static function main():Void {
		var main = new Main();
	}
	
	private inline function new() {
		Browser.window.onload = onWindowLoaded;
	}
	
	private inline function onWindowLoaded():Void {
		var gameDiv = Browser.document.createElement("attach");
		
		// WebGL support check
		var glSupported:WebGLSupport = Detector.detect();
		if (glSupported != SUPPORTED_AND_ENABLED) {
			var unsupportedInfo = Browser.document.createElement('div');
			unsupportedInfo.style.position = 'absolute';
			unsupportedInfo.style.top = '10px';
			unsupportedInfo.style.width = '100%';
			unsupportedInfo.style.textAlign = 'center';
			unsupportedInfo.style.color = '#ffffff';
			
			switch(glSupported) {
				case WebGLSupport.NOT_SUPPORTED:
					unsupportedInfo.innerHTML = 'Your browser does not support WebGL. Click <a href="' + REPO_URL + '" target="_blank">here for project info</a> instead.';
				case WebGLSupport.SUPPORTED_BUT_DISABLED:
					unsupportedInfo.innerHTML = 'Your browser supports WebGL, but the feature appears to be disabled. Click <a href="' + REPO_URL + '" target="_blank">here for project info</a> instead.';
				default:
					unsupportedInfo.innerHTML = 'Could not detect WebGL support. Click <a href="' + REPO_URL + '" target="_blank">here for project info</a> instead.';
			}
			
			gameDiv.appendChild(unsupportedInfo);
			return;
		}
		
		// Setup WebGL renderer
        renderer = new WebGLRenderer( { antialias: true } );
		
		// WebGL extensions support check
		var extDerivatives = 'OES_standard_derivatives';
		var ext = renderer.context.getExtension(extDerivatives);
		if (ext == null) {
			var missingExtensionInfo = Browser.document.createElement('div');
			missingExtensionInfo.style.position = 'absolute';
			missingExtensionInfo.style.top = '10px';
			missingExtensionInfo.style.width = '100%';
			missingExtensionInfo.style.textAlign = 'center';
			missingExtensionInfo.style.color = '#ffffff';
			missingExtensionInfo.innerHTML = 'Missing required WebGL extension: ' + extDerivatives + ' Click <a href="' + REPO_URL + '" target="_blank">here for project info</a> instead.';
			gameDiv.appendChild(missingExtensionInfo);
			return;
		}
		
        renderer.sortObjects = false;
		renderer.autoClear = false;
		renderer.setClearColor(new Color(0x000000));
		renderer.setPixelRatio(Browser.window.devicePixelRatio);
		
		// Attach game div
		gameAttachPoint = Browser.document.getElementById("game");
		gameAttachPoint.appendChild(gameDiv);
		
		var width = Browser.window.innerWidth * renderer.getPixelRatio();
		var height = Browser.window.innerHeight * renderer.getPixelRatio();
		
		scene = new Scene();
		camera = new PerspectiveCamera(75, width / height, 1, 10000);
		camera.position.z = 300;
		
		// Setup composer
		composer = new EffectComposer(renderer);
		var renderPass = new RenderPass(scene, camera);
		composer.addPass(renderPass);
		
		var fxaaMaterial = new ShaderMaterial( {
			vertexShader: FXAA.vertexShader,
			fragmentShader: FXAA.fragmentShader,
			uniforms: FXAA.uniforms
		});
		//fxaaMaterial.uniforms.tDiffuse.value 
		//fxaaMaterial.uniforms.resolution.value.set(width, height);
		
		var aaPass = new ShaderPass(fxaaMaterial);
		composer.addPass(aaPass);
		
		var copyPass = new ShaderPass(CopyShader);
		composer.addPass(copyPass);
		copyPass.renderToScreen = true;
		
		// Initial renderer setup
		// Connect signals and slots
		signal_windowResized.add(function():Void {
			var width = Browser.window.innerWidth * renderer.getPixelRatio();
			var height = Browser.window.innerHeight * renderer.getPixelRatio();
			
			renderer.setSize(width, height);
			
			camera.aspect = width / height;
			camera.updateProjectionMatrix();
		});
		signal_windowResized.dispatch();
		
		sdfMaker = new SDFMaker(renderer);
		
		sdfMaker.signal_textureLoaded.add(function(tag:Dynamic, target:WebGLRenderTarget):Void {
			//trace("Loaded texture with tag: " + tag + " to target: " + target);
			sdfMap.set(tag, target);
			
			var geometry = new PlaneGeometry(target.width, target.height);			
			var mesh = new Mesh(geometry);
			
			// Setup materials
			var aaMaterial = new ShaderMaterial({
				vertexShader: EDT_DISPLAY_AA.vertexShader,
				fragmentShader: EDT_DISPLAY_AA.fragmentShader,
				uniforms: EDT_DISPLAY_AA.uniforms
			});
			aaMaterial.derivatives = true;
			aaMaterial.uniforms.tDiffuse.value = target;
			aaMaterial.uniforms.texw.value = target.width;
			aaMaterial.uniforms.texh.value = target.height;
			aaMaterial.uniforms.texLevels.value = sdfMaker.texLevels;
			aaMaterial.uniforms.threshold.value = 0.0;
			
			aaMaterials.push( { mesh: mesh, material: aaMaterial, sdf: target } );
		
			var rgbMaterial = new ShaderMaterial({
				vertexShader: EDT_DISPLAY_RGB.vertexShader,
				fragmentShader: EDT_DISPLAY_RGB.fragmentShader,
				uniforms: EDT_DISPLAY_RGB.uniforms
			});
			rgbMaterial.uniforms.tDiffuse.value = target;
			rgbMaterial.uniforms.texw.value = target.width;
			rgbMaterial.uniforms.texh.value = target.height;
			rgbMaterial.uniforms.texLevels.value = sdfMaker.texLevels;
			
			rgbMaterials.push( { mesh: mesh, material: rgbMaterial, sdf: target } );
			
			var alphaThresholdMaterial = new ShaderMaterial({
				vertexShader: EDT_DISPLAY_ALPHA_THRESHOLD.vertexShader,
				fragmentShader: EDT_DISPLAY_ALPHA_THRESHOLD.fragmentShader,
				uniforms: EDT_DISPLAY_ALPHA_THRESHOLD.uniforms
			});
			alphaThresholdMaterial.derivatives = true;
			alphaThresholdMaterial.uniforms.tDiffuse.value = target;
			alphaThresholdMaterial.uniforms.texw.value = target.width;
			alphaThresholdMaterial.uniforms.texh.value = target.height;
			alphaThresholdMaterial.uniforms.texLevels.value = sdfMaker.texLevels;
			alphaThresholdMaterial.uniforms.threshold.value = 0.0;
			
			alphaThresholdMaterials.push( { mesh: mesh, material: alphaThresholdMaterial, sdf: target } );
			
			var overlayMaterial = new ShaderMaterial({
				vertexShader: EDT_DISPLAY_OVERLAY.vertexShader,
				fragmentShader: EDT_DISPLAY_OVERLAY.fragmentShader,
				uniforms: EDT_DISPLAY_OVERLAY.uniforms
			});
			overlayMaterial.derivatives = true;
			overlayMaterial.uniforms.tDiffuse.value = target;
			overlayMaterial.uniforms.texw.value = target.width;
			overlayMaterial.uniforms.texh.value = target.height;
			overlayMaterial.uniforms.texLevels.value = sdfMaker.texLevels;
			overlayMaterial.uniforms.threshold.value = 0.0;
			
			overlayMaterials.push( { mesh: mesh, material: overlayMaterial, sdf: target } );
			
			var copyMaterial = new ShaderMaterial( {
				vertexShader: Copy.vertexShader,
				fragmentShader: Copy.fragmentShader,
				uniforms: Copy.uniforms
			});
			copyMaterial.uniforms.tDiffuse.value = target;
			
			copyMaterials.push( { mesh: mesh, material: copyMaterial, sdf: target } );
			
			mesh.material = aaMaterial;
			scene.add(mesh);
			
			setupGUI();
		});
		
		loadTexture("assets/test2.png");
		
		// TODO notify on context loss
		
		// Event setup
		// Window resize event
		Browser.window.addEventListener("resize", function():Void {
			signal_windowResized.dispatch();
		}, true);
		
		// Disable context menu opening
		Browser.window.addEventListener("contextmenu", function(event) {
			event.preventDefault();
		}, true);
		
		Browser.window.addEventListener("keypress", function(event) {
			var keycode = event.keycode;
			
			event.preventDefault();
		}, true);
		
		#if debug
		// Setup performance stats
		setupStats();
		#end
		
		// Present game and start animation loop
		gameDiv.appendChild(renderer.domElement);
		Browser.window.requestAnimationFrame(animate);
	}
	
	private inline function loadTexture(url:String):Void {
		var texture = ImageUtils.loadTexture(url, Mapping.UVMapping, function(texture:Texture):Void {
			sdfMaker.transformTexture(texture);
		});
	}
	
	private function animate(time:Float):Void {
		#if debug
		stats.begin();
		#end
		
		dt = (time - lastAnimationTime) * 0.001; // Seconds
		lastAnimationTime = time;
		
		renderer.render(scene, camera);
		
		Browser.window.requestAnimationFrame(animate);
		
		#if debug
		stats.end();
		#end
	}
	
	private function setupGUI():Void {
		ThreeObjectGUI.addItem(sceneGUI, camera, "World Camera");
		ThreeObjectGUI.addItem(sceneGUI, scene, "Scene");
		
		shaderGUI.add(this, "displayShader", displayShaders).listen().onChange(onDisplayShaderChanged).name("Display Shader");
		
		ShaderGUI.generate(shaderGUI, "FXAA", FXAA.uniforms);
		ShaderGUI.generate(shaderGUI, "AA", EDT_DISPLAY_AA.uniforms);
		ShaderGUI.generate(shaderGUI, "RGB", EDT_DISPLAY_RGB.uniforms);
		ShaderGUI.generate(shaderGUI, "ALPHA_THRESHOLD", EDT_DISPLAY_ALPHA_THRESHOLD.uniforms);
		ShaderGUI.generate(shaderGUI, "OVERLAY", EDT_DISPLAY_OVERLAY.uniforms);
		ShaderGUI.generate(shaderGUI, "COPY", Copy.uniforms);
	}
	
	private function onAntiAliasingShaderChanged(id:String):Void {
		switch(id) {
			case "FXAA":
				
		}
	}
	
	private function onDisplayShaderChanged(id:String):Void {		
		switch(id) {
			case "AA":
				for (o in aaMaterials) {
					o.mesh.material = o.material;
				}
			case "RGB":
				for (o in rgbMaterials) {
					o.mesh.material = o.material;
				}
			case "ALPHA_THRESHOLD":
				for (o in alphaThresholdMaterials) {
					o.mesh.material = o.material;
				}
			case "OVERLAY":
				for (o in overlayMaterials) {
					o.mesh.material = o.material;
				}
			case "COPY":
				for (o in copyMaterials) {
					o.mesh.material = o.material;
				}
		}
	}
	
	#if debug
	private inline function setupStats(mode:Mode = Mode.MEM):Void {
		Sure.sure(stats == null);
		stats = new Stats();
		stats.domElement.style.position = 'absolute';
		stats.domElement.style.left = '0px';
		stats.domElement.style.top = '0px';
		Browser.window.document.body.appendChild(stats.domElement);
	}
	#end
}
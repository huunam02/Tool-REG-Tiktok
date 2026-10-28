/* global exportFunction, cloneInto */
(() => {
  'use strict';
  // Run synchronously at document_start in every frame. Export getters into
  // the page realm directly so CSP does not block an inline script or eval.
  const page = window.wrappedJSObject;
  const define = (target, key, value) => {
    try {
      Object.defineProperty(target, key, {
        get: exportFunction(() => value, page),
        enumerable: true,
        configurable: true,
      });
    } catch (error) {
      console.warn(`Firefox desktop identity: ${key}`, error);
    }
  };
  // hardwareConcurrency stays native: workers cannot be patched, so a window
  // value differing from theirs gives the override away.
  define(page.Navigator.prototype, 'maxTouchPoints', 0);
  // Desktop Firefox without a touchscreen exposes no touch interfaces or
  // ontouch* handlers, and has no window.orientation.
  const remove = (target, keys) => {
    for (const key of keys) {
      try {
        delete target[key];
      } catch (error) {
        console.warn(`Firefox desktop identity: ${key}`, error);
      }
    }
  };
  const touchHandlers = ['ontouchstart', 'ontouchend', 'ontouchmove', 'ontouchcancel'];
  for (const name of ['Window', 'Document', 'HTMLElement', 'SVGElement', 'MathMLElement']) {
    if (page[name]) remove(page[name].prototype, touchHandlers);
  }
  remove(page, [...touchHandlers, 'TouchEvent', 'Touch', 'TouchList']);
  remove(page.Window.prototype, ['orientation', 'onorientationchange']);
  remove(page, ['orientation', 'onorientationchange']);
  define(page.ScreenOrientation.prototype, 'type', 'landscape-primary');
  define(page.ScreenOrientation.prototype, 'angle', 0);
  // A 1920 x 1080 screen at 100% (keep in step with FirefoxDesktopIdentity):
  // the taskbar takes 40 px, and a maximized window overhangs it by 8 px.
  for (const [key, value] of Object.entries({
    width: 1920, height: 1080, availWidth: 1920, availHeight: 1040,
    availLeft: 0, availTop: 0, left: 0, top: 0, colorDepth: 24, pixelDepth: 24,
  })) define(page.Screen.prototype, key, value);
  define(page, 'outerWidth', 1936);
  define(page, 'outerHeight', 1056);
  for (const key of ['screenX', 'screenY', 'screenLeft', 'screenTop']) define(page, key, -8);
  define(page, 'devicePixelRatio', 1);

  // Recompute a native getter from its own value, per event or object.
  const wrapGetter = (proto, key, compute) => {
    try {
      const original = Object.getOwnPropertyDescriptor(proto, key).get;
      Object.defineProperty(proto, key, {
        get: exportFunction(function () { return compute(original.call(this), this); }, page),
        enumerable: true,
        configurable: true,
      });
    } catch (error) {
      console.warn(`Firefox desktop identity: ${key}`, error);
    }
  };
  // The reference PC is driven with a mouse; a finger tap must not show up
  // as a touch pointer (TikTok sends touch devices to its app).
  const pointerProto = page.PointerEvent.prototype;
  const nativePointerType = Object.getOwnPropertyDescriptor(pointerProto, 'pointerType').get;
  const nativeButtons = Object.getOwnPropertyDescriptor(page.MouseEvent.prototype, 'buttons').get;
  const fromTouch = (event) => nativePointerType.call(event) === 'touch';
  wrapGetter(pointerProto, 'pointerType', (value) => (value === 'touch' ? 'mouse' : value));
  for (const key of ['width', 'height']) {
    wrapGetter(pointerProto, key, (value, event) => (fromTouch(event) ? 1 : value));
  }
  wrapGetter(pointerProto, 'pressure', (value, event) =>
    (fromTouch(event) ? (nativeButtons.call(event) ? 0.5 : 0) : value));
  // MouseEvent.MOZ_SOURCE_TOUCH (5) becomes MOZ_SOURCE_MOUSE (1).
  wrapGetter(page.MouseEvent.prototype, 'mozInputSource', (value) => (value === 5 ? 1 : value));

  // Android plays HLS natively; Firefox on Windows does not.
  const canPlayType = page.HTMLMediaElement.prototype.canPlayType;
  page.HTMLMediaElement.prototype.canPlayType = exportFunction(function (type) {
    return /^\s*application\/(vnd\.apple\.mpegurl|x-mpegurl)/i.test(String(type))
      ? '' : canPlayType.call(this, type);
  }, page);

  // The reference PCs' WebGL (Firefox 158, ANGLE/D3D11): the plain RENDERER
  // string, limits, extension list and MSAA. The configuration's GPU arrives
  // as the unmasked renderer FirefoxDesktopIdentity.Gpu sets; keep the keys
  // in step with it. The measured GPUs differ only in these values.
  const gpus = {
    'ANGLE (AMD, Radeon R9 200 Series Direct3D11 vs_5_0 ps_5_0), or similar': { MAX_SAMPLES: 8 },
    'ANGLE (Intel, Intel(R) HD Graphics 400 Direct3D11 vs_5_0 ps_5_0), or similar': { MAX_SAMPLES: 16 },
    'ANGLE (Intel, Intel(R) HD Graphics Direct3D11 vs_5_0 ps_5_0), or similar': { MAX_SAMPLES: 16 },
  };
  const common = {
    MAX_TEXTURE_SIZE: 16384, MAX_CUBE_MAP_TEXTURE_SIZE: 16384,
    MAX_RENDERBUFFER_SIZE: 16384, MAX_VIEWPORT_DIMS: ['Int32Array', 32767, 32767],
    MAX_VERTEX_ATTRIBS: 16, MAX_VERTEX_UNIFORM_VECTORS: 4096, MAX_FRAGMENT_UNIFORM_VECTORS: 1024,
    MAX_VARYING_VECTORS: 30, MAX_TEXTURE_IMAGE_UNITS: 16, MAX_VERTEX_TEXTURE_IMAGE_UNITS: 16,
    MAX_COMBINED_TEXTURE_IMAGE_UNITS: 32, ALIASED_LINE_WIDTH_RANGE: ['Float32Array', 1, 1],
    ALIASED_POINT_SIZE_RANGE: ['Float32Array', 1, 1024], SAMPLES: 4, SAMPLE_BUFFERS: 1,
  };
  // All three Firefox 158 reference PCs report [127, 127, 23] for every
  // supported floating-point shader format. Integer formats have precision
  // zero and keep their native values. Preserve native objects and checks.
  const precisionProto = page.WebGLShaderPrecisionFormat && page.WebGLShaderPrecisionFormat.prototype;
  if (precisionProto) {
    const nativePrecision = Object.getOwnPropertyDescriptor(precisionProto, 'precision').get;
    for (const [index, key] of ['rangeMin', 'rangeMax', 'precision'].entries()) {
      wrapGetter(precisionProto, key, (value, format) =>
        nativePrecision.call(format) > 0 ? [127, 127, 23][index] : value);
    }
  }
  const webgl = {
    WebGLRenderingContext: {
      params: common,
      extensions: ['ANGLE_instanced_arrays', 'EXT_blend_minmax', 'EXT_color_buffer_half_float',
        'EXT_depth_clamp', 'EXT_float_blend', 'EXT_frag_depth', 'EXT_polygon_offset_clamp', 'EXT_sRGB',
        'EXT_shader_texture_lod', 'EXT_texture_compression_bptc', 'EXT_texture_compression_rgtc',
        'EXT_texture_filter_anisotropic', 'OES_element_index_uint', 'OES_fbo_render_mipmap',
        'OES_standard_derivatives', 'OES_texture_float', 'OES_texture_float_linear',
        'OES_texture_half_float', 'OES_texture_half_float_linear', 'OES_vertex_array_object',
        'WEBGL_color_buffer_float', 'WEBGL_compressed_texture_s3tc', 'WEBGL_compressed_texture_s3tc_srgb',
        'WEBGL_debug_renderer_info', 'WEBGL_debug_shaders', 'WEBGL_depth_texture', 'WEBGL_draw_buffers',
        'WEBGL_lose_context', 'WEBGL_provoking_vertex'],
    },
    WebGL2RenderingContext: {
      params: Object.assign({}, common, {
        MAX_3D_TEXTURE_SIZE: 2048, MAX_ARRAY_TEXTURE_LAYERS: 2048, MAX_COLOR_ATTACHMENTS: 8,
        MAX_DRAW_BUFFERS: 8, MAX_UNIFORM_BUFFER_BINDINGS: 24,
        MAX_UNIFORM_BLOCK_SIZE: 65536, MAX_VERTEX_UNIFORM_COMPONENTS: 16384,
        MAX_FRAGMENT_UNIFORM_COMPONENTS: 4096, MAX_ELEMENT_INDEX: 4294967294, MAX_SERVER_WAIT_TIMEOUT: 0,
      }),
      extensions: ['EXT_color_buffer_float', 'EXT_depth_clamp', 'EXT_float_blend',
        'EXT_polygon_offset_clamp', 'EXT_texture_compression_bptc', 'EXT_texture_compression_rgtc',
        'EXT_texture_filter_anisotropic', 'OES_draw_buffers_indexed', 'OES_texture_float_linear',
        'OVR_multiview2', 'WEBGL_compressed_texture_s3tc', 'WEBGL_compressed_texture_s3tc_srgb',
        'WEBGL_debug_renderer_info', 'WEBGL_debug_shaders', 'WEBGL_lose_context', 'WEBGL_provoking_vertex'],
    },
  };
  // Read once per document, on the first query, from the context itself.
  let renderer;
  const rendererOf = (context, getParameter, getExtension) => {
    if (renderer === undefined) {
      let value = null;
      try {
        // UNMASKED_RENDERER_WEBGL; the extension must be enabled to read it.
        if (getExtension.call(context, 'WEBGL_debug_renderer_info')) {
          value = getParameter.call(context, 0x9246);
        }
      } catch (error) {
        console.warn('Firefox desktop identity: renderer', error);
      }
      renderer = Object.prototype.hasOwnProperty.call(gpus, value) ? value : Object.keys(gpus)[0];
    }
    return renderer;
  };
  for (const [name, spec] of Object.entries(webgl)) {
    const proto = page[name] && page[name].prototype;
    if (!proto) continue;
    let values;
    const valuesFor = (gpu) => {
      if (values) return values;
      values = new Map();
      for (const [key, value] of Object.entries({ ...spec.params, ...gpus[gpu], RENDERER: gpu })) {
        if (proto[key] !== undefined) values.set(proto[key], value);
      }
      return values;
    };
    const extensions = new Set(spec.extensions);
    const { getParameter, getSupportedExtensions, getExtension, getContextAttributes } = proto;
    proto.getParameter = exportFunction(function (pname) {
      const values = valuesFor(rendererOf(this, getParameter, getExtension));
      if (!values.has(pname)) return getParameter.call(this, pname);
      const value = values.get(pname);
      if (!Array.isArray(value)) return value;
      return new page[value[0]](cloneInto(value.slice(1), page));
    }, page);
    proto.getSupportedExtensions = exportFunction(function () {
      return getSupportedExtensions.call(this) === null ? null : cloneInto(spec.extensions, page);
    }, page);
    proto.getExtension = exportFunction(function (extension) {
      return extensions.has(String(extension)) ? getExtension.call(this, extension) : null;
    }, page);
    proto.getContextAttributes = exportFunction(function () {
      const attributes = getContextAttributes.call(this);
      if (attributes) attributes.antialias = true;
      return attributes;
    }, page);
  }

  // Desktop Firefox gates Web MIDI behind a site permission add-on.
  remove(page.Navigator.prototype, ['requestMIDIAccess']);

  // The reference PC's Windows speech voices (Android lists Google voices).
  const voiceProto = page.SpeechSynthesisVoice && page.SpeechSynthesisVoice.prototype;
  if (voiceProto) {
    const voices = ['David', 'Mark', 'Zira', 'David Desktop', 'Zira Desktop'].map((who, index) => {
      const name = `Microsoft ${who} - English (United States)`;
      const voice = page.Object.create(voiceProto);
      for (const [key, value] of Object.entries({
        voiceURI: `urn:moz-tts:sapi:${name}?en-US`, name, lang: 'en-US', localService: true, default: index === 0,
      })) Object.defineProperty(voice, key, { value, enumerable: true });
      return voice;
    });
    page.SpeechSynthesis.prototype.getVoices = exportFunction(function () {
      const list = new page.Array();
      for (const voice of voices) list.push(voice);
      return list;
    }, page);
  }
})();

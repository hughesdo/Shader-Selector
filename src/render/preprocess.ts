import type { Dialect, PassInput } from '../library/schema';

/**
 * Turns pass source into WebGL2 (GLSL ES 3.00) fragment source.
 * Returns the source plus how many lines were injected ahead of the user's code,
 * so compile errors can be reported against the original line numbers.
 */
export interface Prepared {
  source: string;
  lineOffset: number;
}

const PRECISION = [
  'precision highp float;',
  'precision highp int;',
  'precision highp sampler2D;',
  'precision highp samplerCube;',
].join('\n');

/** Desktop GLSL -> ES 3.00 fixups that are safe to apply blindly. */
function esFixups(src: string): string {
  return src
    .replace(/^﻿/, '')
    .replace(/\btexture2D\s*\(/g, 'texture(')
    .replace(/\btextureCube\s*\(/g, 'texture(')
    .replace(/\btexture2DLod\s*\(/g, 'textureLod(')
    .replace(/^\s*#extension[^\n]*$/gm, '');
}

const FRAG_OUT = 'shaderlibFragColor';

function prepareFull(code: string): Prepared {
  // Desktop GL tolerates comments above #version, ES does not. Blank the original
  // #version line (keeps the author's line numbers) and put ours on line 1.
  let src = esFixups(code);

  // A few gl-transitions predate GLSL 330 and still write gl_FragColor, which
  // does not exist in ES 3.00. Swap it for a declared out variable. This cannot
  // be a #define: macro names beginning with gl_ are reserved and rejected.
  // Only do it when the file has not already declared its own output.
  const legacyOut = /\bgl_FragColor\b/.test(src) && !/\bout\s+vec4\s+\w+\s*;/.test(src);
  if (legacyOut) src = src.replace(/\bgl_FragColor\b/g, FRAG_OUT);

  const lines = src.split('\n');
  const vi = lines.findIndex((l) => /^\s*#version\b/.test(l));
  if (vi >= 0) lines[vi] = '';
  const decl = legacyOut ? `out vec4 ${FRAG_OUT};\n` : '';
  const head = `#version 300 es\n${PRECISION.replace(/\n/g, ' ')}\n${decl}`;
  return { source: head + lines.join('\n'), lineOffset: legacyOut ? 3 : 2 };
}

function prepareShadertoy(code: string, common: string, inputs: PassInput[], isImage: boolean): Prepared {
  const samplerDecl = [0, 1, 2, 3]
    .map((ch) => {
      const inp = inputs.find((i) => i.channel === ch);
      const t = inp?.type === 'cubemap' ? 'samplerCube' : 'sampler2D';
      return `uniform ${t} iChannel${ch};`;
    })
    .join('\n');
  const header = [
    '#version 300 es',
    PRECISION,
    'uniform vec3 iResolution;',
    'uniform float iTime;',
    'uniform float iTimeDelta;',
    'uniform float iFrameRate;',
    'uniform int iFrame;',
    'uniform vec4 iMouse;',
    'uniform vec4 iDate;',
    'uniform float iSampleRate;',
    'uniform float iChannelTime[4];',
    'uniform vec3 iChannelResolution[4];',
    samplerDecl,
    'out vec4 shaderlibFragColor;',
    esFixups(common),
    '',
  ].join('\n');
  const footer = `\nvoid main() {\n  vec4 c = vec4(0.0);\n  mainImage(c, gl_FragCoord.xy);\n  shaderlibFragColor = ${isImage ? 'vec4(c.rgb, 1.0)' : 'c'};\n}\n`;
  return { source: header + esFixups(code) + footer, lineOffset: header.split('\n').length - 1 };
}

export function prepareFragment(
  dialect: Dialect,
  code: string,
  opts: { common?: string; inputs: PassInput[]; isImage: boolean },
): Prepared {
  // gl-transition is handled by prepareFull on purpose: these files already carry
  // their own #version, uniforms, `out vec4 outColor` and main(), so the only work
  // is the 330 -> ES 3.00 rewrite. What makes them transitions is how the host
  // binds from/to and drives progress, not how the source is assembled.
  return dialect === 'shadertoy'
    ? prepareShadertoy(code, opts.common ?? '', opts.inputs, opts.isImage)
    : prepareFull(code);
}

export const VERTEX_SRC = `#version 300 es
void main() {
  // Fullscreen triangle, no vertex buffer needed.
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

/** Rewrites "ERROR: 0:123:" line numbers back to the author's line numbers. */
export function remapErrors(log: string, lineOffset: number): string {
  return log.replace(/(ERROR|WARNING): 0:(\d+):/g, (_m, kind, n) => `${kind}: line ${Math.max(1, +n - lineOffset)}:`);
}

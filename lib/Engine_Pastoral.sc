// Engine_Pastoral (v11.9 - diagnostics only: postln lines for tone1_load_at (slot/channels/frames), rec_start and rec_stop (frames/path) so maiden's sc tab can show whether buffers load and how long a take was. v11.8 - free() now frees the persistent wind/FX/recorder synths (the wind synth is endless noise with no envelope, and the old free() only freed buses/buffers, so the wind alone kept sounding after switching scripts); tone1 samples moved to a 64-slot buffer pool: tone1_load_at "is" loads per slot and retires a replaced buffer with a 14s delayed free so a ringing note is never cut, pluck_sample_at "fffffi" plays any slot so consecutive notes can use different samples and always ring out fully; recorder synth now placed in the engine group. v11.7 - bell (tone2) sparkle and definition: added 5.43x/6.79x high partials whose level follows the brightness value, a bright high-frequency strike transient instead of the old 2500Hz-lowpassed click, brightness LPF widened to 2000-16000Hz, tanh softening removed from the bell, and direct/reverb-send balance changed from 0.4/0.9 to 0.6/0.6 so the contour is not washed out. v11.6 wider master tone, v11.5 Balance2 fix, v11.4 audio-input sample recording, v11.3 tone1 samples, v11.2 granular range, v11.1 overlap compensation kept)
Engine_Pastoral : CroneEngine {
    var <synthPluck;
    var <synthBell;
    var <synthWind;
    var <synthFX;
    var <busDry;
    var <busRev;
    var <bufGranular;
    var <bufPool;
    var <bufRetired;
    var <bufRec;
    var <recSynth;
    var <recStartTime;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        busDry = Bus.audio(context.server, 2);
        busRev = Bus.audio(context.server, 2);

        // mono circular buffer for the granular cloud (2.5 s)
        bufGranular = Buffer.alloc(context.server, context.server.sampleRate * 2.5, 1);
        // sample recording buffer (max 12 s, stereo)
        bufRec = Buffer.alloc(context.server, context.server.sampleRate * 12, 2);
        bufPool = Array.newClear(64);
        bufRetired = List.new;

        // 1. wind ambience
        SynthDef(\pastoralWind, {
            arg out = 0, amp = 0.3, windSpeed = 35, tone = 0.5;
            var noise, sig, lfo, cutoff;
            lfo = LFNoise1.kr(0.08 + (windSpeed * 0.004)).bipolar(1);
            cutoff = ((130 + (windSpeed * 5) + (lfo * 50)) * (0.3 + (tone * 1.7))).clip(50, 4000);
            noise = PinkNoise.ar(0.7) + BrownNoise.ar(0.3);
            sig = BPF.ar(noise, cutoff, 0.4) * 2.8;
            sig = Pan2.ar(sig * amp, lfo * 0.3);
            Out.ar(out, sig);
        }).add;

        // 2. pluck (tone1 synth voice)
        SynthDef(\pastoralPluck, {
            arg out = 0, send = 0, freq = 220, amp = 0.8, pan = 0, release = 2.8;
            var excite, sig, env, bodyAir, bodyWood;

            env = EnvGen.kr(Env.perc(0.003, release, amp), doneAction: 2);
            excite = LPF.ar(PinkNoise.ar(), 650) * Decay2.ar(Impulse.ar(0), 0.004, 0.035);
            excite = excite + (SinOsc.ar(freq * 0.5) * Decay.ar(Impulse.ar(0), 0.02) * 0.2);

            sig = Pluck.ar(excite, 1, 1/freq, 1/freq, release, 0.6);

            bodyAir = BPF.ar(sig, 108, 0.35) * 2.2;
            bodyWood = BPF.ar(sig, 240, 0.3) * 1.6 + BPF.ar(sig, 420, 0.25) * 1.1;

            sig = (sig * 0.45) + (bodyAir * 0.3) + (bodyWood * 0.25);
            sig = LPF.ar(sig, (freq * 2.5).clip(450, 3800));
            sig = LeakDC.ar(sig) * env * 8.5;
            sig = sig.tanh;

            Out.ar(out, Pan2.ar(sig * 0.8, pan));
            Out.ar(send, Pan2.ar(sig * 0.6, pan));
        }).add;

        // 2b. tone1 sample playback (mono): pitch set by playback rate
        SynthDef(\pastoralSampleMono, {
            arg out = 0, send = 0, bufnum = 0, freq = 220, baseFreq = 220, amp = 0.8, pan = 0, release = 12;
            var rate, sig, env;
            rate = freq / baseFreq;
            sig = PlayBuf.ar(1, bufnum, rate * BufRateScale.kr(bufnum), doneAction: 2);
            env = EnvGen.kr(Env.perc(0.003, release, amp));
            sig = LPF.ar(sig, (freq * 2.5).clip(450, 8000));
            sig = LeakDC.ar(sig) * env;
            Out.ar(out, Pan2.ar(sig * 0.8, pan));
            Out.ar(send, Pan2.ar(sig * 0.6, pan));
        }).add;

        // 2c. tone1 sample playback (stereo)
        SynthDef(\pastoralSampleStereo, {
            arg out = 0, send = 0, bufnum = 0, freq = 220, baseFreq = 220, amp = 0.8, pan = 0, release = 12;
            var rate, sig, env;
            rate = freq / baseFreq;
            sig = PlayBuf.ar(2, bufnum, rate * BufRateScale.kr(bufnum), doneAction: 2);
            env = EnvGen.kr(Env.perc(0.003, release, amp));
            sig = LPF.ar(sig, (freq * 2.5).clip(450, 8000));
            sig = LeakDC.ar(sig) * env;
            Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * 0.8);
            Out.ar(send, Balance2.ar(sig[0], sig[1], pan) * 0.6);
        }).add;

        // 3. fiddle
        SynthDef(\pastoralFiddle, {
            arg out = 0, send = 0, freq = 440, amp = 0.35, pan = 0, dur = 6.0, att = 1.0;
            var env, vib, bowNoise, sig, body, sus, rel;

            rel = (dur * 0.35).clip(1.2, 3.0);
            att = att.min(dur * 0.5);
            sus = (dur - att - rel).max(0.05);

            vib = SinOsc.kr(5.1, 0, 0.012) * EnvGen.kr(Env([0, 0, 1], [att * 0.8, att]));
            freq = freq * (1 + vib);

            bowNoise = BPF.ar(PinkNoise.ar(0.1), (freq * 2.2).clip(350, 6000), 0.3);
            sig = Saw.ar(freq) + (Pulse.ar(freq * 0.999, 0.4) * 0.4) + bowNoise;

            body = BPF.ar(sig, 520, 0.35) * 1.7 + BPF.ar(sig, 1250, 0.3) * 1.2 + BPF.ar(sig, 2600, 0.25) * 0.8;
            sig = (sig * 0.22) + (body * 0.78);
            sig = LPF.ar(sig, (freq * 3.8).clip(600, 6500));

            env = EnvGen.kr(Env([0, 1, 0.85, 0], [att, sus, rel], [\sine, \welch, \sine]), doneAction: 2);
            sig = sig * env * amp;

            Out.ar(out, Pan2.ar(sig * 0.65, pan));
            Out.ar(send, Pan2.ar(sig * 0.85, pan));
        }).add;

        // 4. church bell (high sparkle partials, bright strike, no tanh so the contour stays clear)
        SynthDef(\pastoralBell, {
            arg out = 0, send = 0, freq = 220, amp = 0.1, pan = 0, bright = 0.85;
            var partials, amps, decays, sig, strike;
            partials = [0.5, 1.0, 1.183, 1.506, 2.0, 2.74, 3.0, 4.07, 5.43, 6.79];
            amps =     [0.7, 1.0, 0.6,   0.4,   0.5, 0.3,  0.2, 0.16, 0.22, 0.16];
            decays =   [6.0, 4.5, 4.0,   3.5,   2.5, 1.8,  1.2, 0.9,  0.55, 0.4];

            sig = Mix.fill(partials.size, { arg i;
                var pFreq = freq * partials[i];
                var pEnv = EnvGen.kr(Env.perc(0.001, decays[i]));
                var pAmp = amps[i] * if(partials[i] > 4.0) { 0.25 + (bright * 1.75) } { 1.0 };
                SinOsc.ar(pFreq) * pEnv * pAmp;
            });

            strike = HPF.ar(WhiteNoise.ar(0.22) * EnvGen.kr(Env.perc(0.001, 0.035)), 3200)
                   + BPF.ar(WhiteNoise.ar(0.18) * EnvGen.kr(Env.perc(0.001, 0.06)), 2600, 0.8);
            sig = sig + (strike * (0.4 + (bright * 0.6)));
            sig = LPF.ar(sig, (2000 + (bright * 14000)).clip(1000, 16000));
            sig = sig * amp * 0.95;
            DetectSilence.ar(sig, 0.0001, doneAction: 2);

            Out.ar(out, Pan2.ar(sig * 0.6, pan));
            Out.ar(send, Pan2.ar(sig * 0.6, pan));
        }).add;

        // recorder: audio input straight into the buffer
        SynthDef(\pastoralRecorder, {
            arg bufnum = 0;
            var sig = SoundIn.ar([0, 1]);
            RecordBuf.ar(sig, bufnum, loop: 0, doneAction: 2);
        }).add;

        // 5. master FX: shimmer reverb + TGrains granular cloud
        SynthDef(\pastoralFX, {
            arg dryBus, revBus, out = 0, cutoff = 3000, shimmer = 0.35,
                grainSize = 0.3, grainMix = 0.0, grainBuf = 0;
            var dry, wet, fbIn, shimmerSig, sig;
            var monoIn, grainTrig, grainPos, grainRate, grainDur, grainSig;
            var grainTrigRate, grainOverlap, grainAmp;

            dry = In.ar(dryBus, 2);
            wet = In.ar(revBus, 2);

            dry = LPF.ar(dry, cutoff.clip(150, 16000));
            wet = LPF.ar(wet, cutoff.clip(150, 12000));

            // record dry + reverb, mono-summed, into the circular buffer
            monoIn = (dry[0] + dry[1]) * 0.5 + (wet[0] * 0.2);
            RecordBuf.ar(monoIn, grainBuf, 0, 1, 0, 1, 1);

            // --- TGrains granular engine ---
            // trigger density (dense cloud up to 60/sec at small sizes, still 18/sec at large sizes)
            grainTrigRate = (18 + (1.0 - grainSize) * 40).clip(10, 60);
            grainTrig = Impulse.ar(grainTrigRate);

            // grain length (20 ms slivers up to 650 ms grains)
            grainDur = (grainSize * 0.6 + 0.02).clip(0.02, 0.65);

            // grains sounding at once (density x length): at max size
            // about 11 overlap, so each grain's amp is scaled down
            // (overlap compensation -- a fixed amp would clip as size grows)
            grainOverlap = grainTrigRate * grainDur;
            grainAmp = 1.5 / grainOverlap.max(1).sqrt;

            // read position inside the buffer (random within the last 2.5 s)
            grainPos = (Phasor.ar(0, 1 / BufFrames.ir(grainBuf), 0, 1) - TRand.kr(0.02, 0.98, grainTrig)).wrap(0, 1);
            grainPos = grainPos * BufDur.ir(grainBuf);

            // mix of forward, reversed, octave up/down and fifth-up rates
            grainRate = TChoose.kr(grainTrig, [1.0, 1.0, -1.0, -2.0, 0.5, 2.0, 1.5, 3.0, 0.25, -0.5]);

            // stereo spread via TGrains
            grainSig = TGrains.ar(
                numChannels: 2,
                trigger: grainTrig,
                bufnum: grainBuf,
                rate: grainRate,
                centerPos: grainPos,
                dur: grainDur,
                pan: TRand.kr(-1.0, 1.0, grainTrig),
                amp: grainAmp,
                interp: 4
            );
            grainSig = LPF.ar(grainSig, 4200) * grainMix;

            // --- shimmer reverb ---
            fbIn = LocalIn.ar(2);
            wet = wet + (fbIn * (shimmer * 0.68).clip(0.0, 0.72)) + (grainSig * 0.25);
            wet = FreeVerb2.ar(wet[0], wet[1], 1.0, (0.65 + shimmer * 0.28).clip(0.5, 0.96), 0.35);

            shimmerSig = PitchShift.ar(wet, 0.14, 2.0, 0.01, 0.02);
            shimmerSig = LPF.ar(shimmerSig, 5000);
            shimmerSig = HPF.ar(shimmerSig, 250);

            LocalOut.ar(shimmerSig);

            // final output (as the grain mix rises, the dry signal ducks slightly and the cloud comes forward)
            sig = (dry * (1.0 - grainMix * 0.35)) + (wet * (0.3 + shimmer * 0.4)) + (shimmerSig * (shimmer * 0.55)) + (grainSig * (0.9 + grainMix * 0.3));
            sig = Limiter.ar(sig, 0.95);
            Out.ar(out, sig);
        }).add;

        context.server.sync;

        context.server.makeBundle(nil, {
            synthWind = Synth.new(\pastoralWind, [\out, context.out_b], context.xg);
            synthFX = Synth.tail(context.xg, \pastoralFX, [
                \dryBus, busDry,
                \revBus, busRev,
                \out, context.out_b,
                \cutoff, 3000,
                \shimmer, 0.35,
                \grainSize, 0.35,
                \grainMix, 0.0,
                \grainBuf, bufGranular
            ]);
        });

        this.addCommand("pluck", "ffff", { arg msg;
            Synth.before(synthFX, \pastoralPluck, [
                \out, busDry, \send, busRev,
                \freq, msg[1], \amp, msg[2], \pan, msg[3], \release, msg[4]
            ]);
        });

        this.addCommand("tone1_load_at", "is", { arg msg;
            var idx = msg[1].asInteger;
            var path = msg[2].asString;
            if ((idx >= 0) and: (idx < bufPool.size)) {
                Buffer.read(context.server, path, 0, -1, { arg buf;
                    var old = bufPool[idx];
                    "pastoral: slot % loaded (% ch, % frames)".format(idx, buf.numChannels, buf.numFrames).postln;
                    buf.normalize(0.8);
                    bufPool[idx] = buf;
                    if (old.notNil and: (old != buf)) {
                        bufRetired.add(old);
                        SystemClock.sched(14, { old.free; bufRetired.remove(old); nil });
                    };
                });
            };
        });

        this.addCommand("pluck_sample_at", "fffffi", { arg msg;
            var idx = msg[6].asInteger;
            var buf = nil;
            if ((idx >= 0) and: (idx < bufPool.size)) { buf = bufPool[idx]; };
            if (buf.notNil and: synthFX.notNil) {
                var defName = if (buf.numChannels > 1) { \pastoralSampleStereo } { \pastoralSampleMono };
                Synth.before(synthFX, defName, [
                    \out, busDry, \send, busRev,
                    \bufnum, buf.bufnum,
                    \freq, msg[1], \amp, msg[2], \pan, msg[3],
                    \release, msg[4], \baseFreq, msg[5]
                ]);
            };
        });

        this.addCommand("rec_start", "", {
            if (recSynth.isNil) {
                recSynth = Synth(\pastoralRecorder, [\bufnum, bufRec.bufnum], context.xg);
                "pastoral: rec_start".postln;
                recStartTime = SystemClock.seconds;
                recSynth.onFree({ recSynth = nil; });
            };
        });

        this.addCommand("rec_stop", "s", { arg msg;
            var path = msg[1].asString;
            var frames;
            if (recSynth.notNil) { recSynth.free; recSynth = nil; };
            if (recStartTime.notNil) {
                frames = ((SystemClock.seconds - recStartTime) * bufRec.sampleRate).floor.asInteger;
                frames = frames.clip(0, bufRec.numFrames);
                "pastoral: rec_stop frames=% path=%".format(frames, path).postln;
                if (frames > 1000) { bufRec.write(path, "wav", "int16", frames, 0); };
                recStartTime = nil;
            };
        });

        this.addCommand("fiddle", "fffff", { arg msg;
            Synth.before(synthFX, \pastoralFiddle, [
                \out, busDry, \send, busRev,
                \freq, msg[1], \amp, msg[2], \pan, msg[3],
                \dur, msg[4], \att, msg[5]
            ]);
        });

        this.addCommand("bell", "ffff", { arg msg;
            Synth.before(synthFX, \pastoralBell, [
                \out, busDry, \send, busRev,
                \freq, msg[1], \amp, msg[2], \pan, msg[3], \bright, msg[4]
            ]);
        });

        this.addCommand("wind_speed", "f", { arg msg;
            if (synthWind.notNil) { synthWind.set(\windSpeed, msg[1]); };
        });

        this.addCommand("wind_amp", "f", { arg msg;
            if (synthWind.notNil) { synthWind.set(\amp, msg[1]); };
        });

        this.addCommand("shimmer", "f", { arg msg;
            if (synthFX.notNil) { synthFX.set(\shimmer, msg[1]); };
        });

        this.addCommand("grain_size", "f", { arg msg;
            if (synthFX.notNil) { synthFX.set(\grainSize, msg[1]); };
        });

        this.addCommand("grain_mix", "f", { arg msg;
            if (synthFX.notNil) { synthFX.set(\grainMix, msg[1]); };
        });

        this.addCommand("cutoff", "f", { arg msg;
            if (synthFX.notNil) { synthFX.set(\cutoff, msg[1]); };
            if (synthWind.notNil) { synthWind.set(\tone, (msg[1] / 16000).clip(0, 1)); };
        });
    }

    free {
        if (synthWind.notNil) { synthWind.free; synthWind = nil; };
        if (synthFX.notNil) { synthFX.free; synthFX = nil; };
        if (recSynth.notNil) { recSynth.free; recSynth = nil; };
        busDry.free;
        busRev.free;
        bufGranular.free;
        bufRec.free;
        bufPool.do({ arg b; if (b.notNil) { b.free }; });
        bufRetired.do({ arg b; if (b.notNil) { b.free }; });
    }
}
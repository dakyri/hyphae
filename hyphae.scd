(
s.waitForBoot({

	Buffer.freeAll;
	s.sync;

	// input synth, mono->mono
	SynthDef(\input, {
		var sig;
		sig = SoundIn.ar(\inBus.ir(0)) * \amp.kr(1);
		SendTrig.kr(Coyote.kr(sig, fastMul: 0.6, thresh: 0.001), \trigId.ir(0), sig);
		Out.ar(\outBus.ir(0), sig);
	}).add;

	// record synth, mono->0
	SynthDef(\rec, {
		var liveSig, loopSig, sig, ptr;
		ptr = In.ar(\inPtr.ir(0), 1);
		sig = In.ar(\inBus.ir(0), 1);
		sig = sig * \amp.kr(1).varlag(\ampLag.kr(5),-2);
		BufWr.ar(sig, \buf.kr(0), ptr);
	}).add;

	// reverb synth, mono->mono
	// maybe better to add to main out nodes directly
	SynthDef.new(\rev, {
		arg in=0, wetamp=0.3, out=0;
		var sig, wet;
		sig = In.ar(\inBus.ir(0));
		wet = FreeVerb.ar(sig, mix: 1.0, room: 1.0, damp: 0.85, mul: wetamp);
		sig = sig + wet;
		Out.ar(\outBus.ir(0), sig);
	}).add;

	// play the thru signal spatialized, mono->quad
	SynthDef(\play, {
		var sig;
		var t = \stepT.kr(0.01)
		sig = In.ar(\inBus.ir(0)) * \amp.kr(1);
		Out.ar(\outBus.ir(0), Pan4.ar(sig, \x.kr(0).varlag(t), \y.kr(0).varlag(t)))
	}).add;

	// play the thru signal spatialized, mono->quad
	// maybe some curve on the lag would be nice
	SynthDef(\strand, {
		var sig;
		var t = \stepT.kr(0.01)
		sig = In.ar(\inBus.ir(0)) * \amp.kr(1);
		Out.ar(\outBus.ir(0), Pan4.ar(sig, \x.kr(0).varlag(t), \y.kr(0).varlag(t)))
	}).add;

/*
 * create global buses and groups
 */
	s.sync;
	s.newBusAllocators;
	~trigBus = Bus.audio(s,1);
	~sweepBus = Bus.audio(s,1);
	~ptrBus = Bus.audio(s,1);
	~micBus = Bus.audio(s,1);
	~micDirectBus = Bus.audio(s,1);
	~loopBus = Bus.audio(s,1);
	~mainOut = 0;

	~inGrp = Group.new;
	~trigGrp = Group.after(~inGrp);
	~sweepGrp = Group.after(~trigGrp);
	~ptrGrp = Group.after(~sweepGrp);
	~playGrp = Group.after(~ptrGrp);
	~recGrp = Group.after(~playGrp);
	~mixerGrp = Group.after(~recGrp);

/*!
 * Mycellium
 * The main wrapper around definitions and codes to map an input onto a recorder,
 * a 2d panned output, and a collection of 'strands' which will be dynamically
 * panned around the space
 */
	~mycellium = (
		type: \composite,
		play: { |self| },
		new: { |self, c_x=0, c_y=0, i_bus=0, o_bus=0, v_in=3|
			self.postln; c_x.postln; c_y.postln; i_bus.postln; o_bus.postln;
			v_in.postln;
			(
				type: \composite,
				center_x: c_x,
				center_y: c_y,
				in_bus: i_bus,
				out_bus: o_bus,
				poop: { |self, x|
					self.center_x = self.center_x + 1;
					self.out_bus.postln;
				}
			)
		}
	)


/*
	SynthDef(\trig, {
		var sig;
		sig = Trig1.ar(\trig.tr(0), ControlDur.ir);
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\sweep, {
		var sig, trigSig;
		trigSig = In.ar(\inTrig.ir(0), 1);
		sig = Sweep.ar(\trig.tr(0) + trigSig, SampleRate.ir * \run.kr(1));
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\ptr, {
		var sig, max, trigSig;
		trigSig = In.ar(\inTrig.ir(0), 1);
		max = In.ar(\inMax.ir(0), 1);
		sig = Phasor.ar(\trig.tr(0) + trigSig, 1, 0, max, 0);
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\play, {
		var sig, ptr;
		ptr = In.ar(\inPtr.ir(0), 1);
		sig = BufRd.ar(1,\buf.kr(0),ptr);
		sig = sig * \amp.kr(1).varlag(\ampLag.kr(5),-2);
		Out.ar(\out.ir(0), sig);
	}).add;

	SynthDef(\mixer, {
		var loop, direct, sig;
		loop = In.ar(\inLoop.ir(0), 1);
		direct = In.ar(\inDirect.ir(0), 1);
		sig = sum([
			loop * \loopAmp.kr(1).varlag(\ampLag.kr(5),-2),
			direct * \directAmp.kr(1).varlag(\ampLag.kr(5),-2)
		]);
		sig = sig * \amp.kr(1).varlag(\ampLag.kr(5),-2);
		Out.ar(\out.ir(0), direct!2);
	}).add;
*/

//	~b = Buffer.alloc(s, s.sampleRate * 300);

	s.sync;

	~my_inport = 0; // a mono port id
	~my_outport = 0; // 1st line of a quad set
	~linein_syn = Synth(
		\input, [
			\inBus, ~my_inport,
			\outBus, ~micBus,
			\amp, 1
		], ~inGrp
	);

});
)
s.reboot
s.scope
s.meter
s.plotTree
s.stop
s.freeAll
{ PinkNoise.ar(0.2) + SinOsc.ar(440, 0, 0.2) + Saw.ar(660, 0.2) }.plot;
ServerOptions.devices
~linein_syn.set(\outBus, 3)

s.boot
(
o = OSCFunc({ arg msg, time;
    [time, msg].postln;
},'/tr', s.addr, argTemplate: [{|x| x.postln; true; }, {|x| x.postln; true; }, {|x| x.postln; true; }]);
)
// [ 1020.053671147, [ /tr, 1005, 0, 0.89999997615814 ] ]
(
SynthDef("help-SendTrig",{SendTrig.kr(Dust.kr(1.0),0,0.9);}).add;
)
(
(
SynthDef("coyote", {  var sounds = Mix.fill(3, { var trig = Dust.kr(1);
                                                 Saw.ar(TRand.kr(50, 880, trig),
                                                        Decay.kr(trig,
                                                                 TRand.kr(0.1, 2, trig),
                                                                 3.reciprocal)); } );

// var detect = PinkNoise.ar(Decay.kr(Coyote.kr(sounds,    fastMul: 0.6,  thresh: 0.001), 0.2));
var sig = Coyote.kr(sounds, fastMul: 0.6, thresh: 0.001);
SendTrig.kr(sig, 0, sig);
                      Out.ar(0, sounds); } ).send(s);
).add
)
x = Synth.new("coyote")
x.free
y = Synth("help-SendTrig");
y.free
true

sum([1, 2, 3, 4, 5])
~linein_syn.play
s.reboot
//initial start record
~looper.set(\trig, 1, \run, 1, \reclev, 1, \prelev, 1, \xfade, 0.02);

//stop recording/overdubbing, begin/continue looping
~looper.set(\run, 0, \reclev, 0, \prelev, 1);

//start overdubbing (slight attenuation on existing content to prevent buildup)
~looper.set(\run, 0, \reclev, 1, \prelev, -1.dbamp);

//gradually fade loop content on each loop, without recording new audio
~looper.set(\run, 0, \reclev, 0, \prelev, -3.dbamp);

//reset, clear buffer, and immediately begin recording again
~b.zero; ~looper.set(\trig, 1, \run, 1, \reclev, 1, \prelev, 1, \xfade, 0.02);

//reset, clear buffer, but do not begin recording again
~b.zero; ~looper.set(\trig, 1, \run, 0, \reclev, 0, \prelev, 0, \xfade, 0.02);

//fade loop signal out of/into main mix
~looper.set(\loopAmp, 0, \xfade, 3);
~looper.set(\loopAmp, 1, \xfade, 3);
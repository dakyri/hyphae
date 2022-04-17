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
	// pointer reset by t_start, running started by \run set to 0
	SynthDef(\rec, { | t_start=1, run=0 |
		var sig, rec_len;
		rec_len = Sweep.ar(t_start, SampleRate.ir * run);
		sig = In.ar(\inBus.ir(0), 1);
		BufWr.ar(sig, \buf.kr(0), rec_len-1);
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
	~recSweepBus = Bus.audio(s,1); // ?? output for record sweep to track length
	~micBus = Bus.audio(s,1); // actually one for each line in
	~strandOutBus = Bus.audio(s, 4); // collective output for processed sound
	~directOutBus = Bus.audio(s, 4); // collective output for direct line
	~mainOut = 0; // audio out, 4 channel. need 3 groups. [0..3], [2..5], and [4..7]

	~inputGrp = Group.new; // group for line inputs
	~trigGrp = Group.after(~inputGrp); // group for any trigger traffic
	~playGrp = Group.after(~trigGrp); // group for direct and strand players
	~recGrp = Group.after(~playGrp); // group for recording line in
	~masterFXGrp = Group.after(~recGrp); // group for any master fx
	~masterOutGrp = Group.after(~masterFXGrp); // group for main hardware io

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
			(
				type: \composite,
				center_x: c_x, // center x of this performer
				center_y: c_y, // center y of this performer
				in_bus: i_bus, // mono linein bus
				out_bus: o_bus, // quad lineout bus
				linein_syn: nil,
				play_syn: nil,
				record_syn: nil,
				osc_rec_trig: nil,

				/*!
				 * just a test stub
				 */
				test_mv: { |self, x|
					self.center_x = self.center_x + 1;
					self.out_bus.postln;
				},
				/*!
				 * clean up any existing stuff and launch our main working synths
				 */
				start: { |self|
					if (self.linein_syn != nil, { self.linein_syn.free; });
					if (self.play_syn != nil, { self.play_syn.free; });
					if (self.record_syn != nil, { self.record_syn.free; });
					if (self.osc_rec_trig != nil, { self.osc_rec_trig.free; });

					self.linein_syn = Synth(\input);
					self.play_syn = Synth(\play);
					self.record_syn = Synth(\rec);
					self.osc_rec_trig = OSCFunc({|msg, time|
						[time, msg].postln;
					},'/tr', argTemplate: [{|x| x == self.linein_syn.nodeID; },
						{|x| x.postln; true; },
						{|x| x.postln; true; }]);
				}

			)
		}
	)


	~b = Buffer.alloc(s, s.sampleRate * 300);

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
(
	~b = Buffer.alloc(s, s.sampleRate * 10);
	SynthDef(\rec, { | t_start=1, run=0 |
		var sig, rec_len;
		rec_len = Sweep.ar(t_start, SampleRate.ir * run);
		sig = SoundIn.ar(0, 1);
	    sig.poll;
		BufWr.ar(sig, \buf.kr(0), rec_len);
	    rec_len.poll;
		Out.ar(0, sig);

	}).add;
)
s.reboot
a = Synth(\rec)
a.set(\buf, ~b.bufnum)
a.set(\run, 1)
a.set(\run, 0)
a.set(\t_start, 1)
~b.plot
~b.bufnum
s.boot
s.freeAll
~b.play
a.free

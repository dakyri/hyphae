(
s.waitForBoot({

	Buffer.freeAll;
	s.sync;

	~onsetTrigId = 1;
	~fallTrigId = 2;

	// input synth, mono->mono
	SynthDef(\input, {
		var sig;
		sig = SoundIn.ar(\inBus.ir(0)) * \amp.kr(1);
		SendTrig.kr(
			Coyote.kr(sig, fastMul: 0.6, thresh: 0.001), \onsetTrigId.ir(~onsetTrigId), sig);
		Out.ar(\outBus.ir(0), sig);
	}).add;

	// record synth, mono->0
	// pointer reset by t_start, running started by \run set to 0
	SynthDef(\rec, { | t_reset=1, run=0 |
		var sig, rec_len;
		rec_len = Sweep.ar(t_reset, SampleRate.ir * run);
		sig = In.ar(\inBus.ir(0), 1);
		BufWr.ar(sig, \buf.kr(0), rec_len-1, loop: 0);
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
	// maybe some curve on the lag would be nice
	SynthDef(\play, {
		var sig;
		var t = \stepT.kr(0.01)
		sig = In.ar(\inBus.ir(0)) * \amp.kr(1);
		Out.ar(\outBus.ir(0), Pan4.ar(sig, \x.kr(0).varlag(t), \y.kr(0).varlag(t)))
	}).add;

	// play the strand signal from the buffer spatialized, none->quad
	// buf reader won't loop. it will be triggered to reset from the controller
	// for the moment, we'll keep things running forward with no pitch shift
	// and generate variety by breaking up and running in different time scales
	SynthDef(\strand, { | run=0, start, end|
		var sig;
		var t = \stepT.kr(0.01)
		var phase = Sweep.ar(\t_start.kr, SampleRate.ir * run).linlin(0, 1, start, end, \minmax);
		sig = BufRd.ar(1, \buf.kr(0), phase);
		sig = sig * \amp.kr(1);
		Out.ar(\outBus.ir(0), Pan4.ar(sig, \x.kr(0).varlag(t), \y.kr(0).varlag(t)))
	}).add;

/*
 * create global buses and groups
 */
	s.sync;
	s.newBusAllocators;
	~recSweepBus = Bus.audio(s,1); // ?? output for record sweep to track length
	~strandOutBus = Bus.audio(s, 4); // collective output for processed sound
	~directOutBus = Bus.audio(s, 4); // collective output for direct line
	~mainOut = 0; // audio out, 4 channel. need 3 groups. [0..3], [2..5], and [4..7]

	~inputGrp = Group.new; // group for line inputs
	~trigGrp = Group.after(~inputGrp); // group for any trigger traffic
	~playGrp = Group.after(~trigGrp); // group for direct and strand players
	~recGrp = Group.after(~playGrp); // group for recording line in
	~masterFXGrp = Group.after(~recGrp); // group for any master fx
	~masterOutGrp = Group.after(~masterFXGrp); // group for main hardware io

/**
 * Hypha
 * Holds data and functionals for a single strand of sound which will be looped
 * and moved along a given path.
 */
	~hypha = (
		type: \composite,
		play: { |self| },
		new: { |self|
			(
				type: \composite,
				cur_ind: 0,
				start_pos: 0,
				end_pos: 0,
				hi_freq: 0,
				lo_freq: 0,
				level: 0,
				path: [], // list of space-time tuples (arrays of x, y, t)
				strand_syn: nil, // the player of this little fandango

				/**
				 *  @return: a shifted copy of self from a
				 */
				branch: { |self, branch_ind|
				}
			)
		}
	);

/**
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
				in_bus: i_bus, // mono linein hardware bus
				out_bus: o_bus, // quad lineout hardware bus
				linein_bus: Bus.audio(s, 1), // mono bus from input -> direct out and recorder
				linein_syn: nil,
				play_syn: nil,
				record_syn: nil,
				osc_rec_trig: nil,

				/**
				 * clean stuff up.
				 */
				free: { |self|
					if (self.linein_syn != nil, { self.linein_syn.free; });
					if (self.play_syn != nil, { self.play_syn.free; });
					if (self.record_syn != nil, { self.record_syn.free; });
					if (self.osc_rec_trig != nil, { self.osc_rec_trig.free; });
				},

				/*!
				 * just a test stub
				 */
				test_mv: { |self, x|
					self.center_x = self.center_x + 1;
					self.out_bus.postln;
				},
				/**
				 * clean up any existing stuff and launch our main working synths
				 */
				start: { |self|
					if (self.linein_syn != nil, { self.linein_syn.free; });
					if (self.play_syn != nil, { self.play_syn.free; });
					if (self.record_syn != nil, { self.record_syn.free; });
					if (self.osc_rec_trig != nil, { self.osc_rec_trig.free; });

					self.linein_syn = Synth(
						\input, [
							\inBus, 1,
							\amp, 1,
							\onsetTrigId, 1,
							\outBus, self.linein_bus,
						], ~inputGrp
					);
					self.play_syn = Synth(
						\play, [
							\inBus, self.linein_bus,
							\amp, 1,
							\outBus, 1,
							\x, self.center_x,
							\y, self.center_y
						], ~playGrp
					);
					self.record_syn = Synth(
						\rec, [
							\inBus, self.linein_bus,
							\buf, 0,
							\t_reset, 1,
							\run, 0,
						], ~recGrp
					);
					self.osc_rec_trig = OSCFunc({|msg, time|
						[time, msg].postln;
					},'/tr', argTemplate: [
						{|x| x == self.linein_syn.nodeID; },
						{|x| x.postln; true; },
						{|x| x.postln; true; }]);
				},
				startRec: { |self|
					if (self.record_syn != nil, {
						self.record_syn.set(\t_reset, 1, \run, 1);
					});
				},
				stopRec: { |self|
					if (self.record_syn != nil, {
						self.record_syn.set(\run, 0);
					});
				},
				setInputLevel: { |self, level|
					if (self.linein_syn != nil, {
						self.linein_syn.set(\amp, level);
					});
				},
				setDirectLevel: { |self, level|
					if (self.play_syn != nil, {
						self.play_syn.set(\amp, level);
					});
				},
				/* this should be at an overall mix level */
				setStrandLevel: { |self, level|
					if (self.play_syn != nil, {
						self.play_syn.set(\amp, level);
					});
				},
				setCenterPos: { |self, x, y|
					self.center_x = x;
					self.center_y = y;
					if (self.play_syn != nil, {
						self.play_syn.set(\x, x, \y, y);
					});
				},
			)
		}
	);

	/*
	 * OSC rescponders.
	 * the 1st param to correspond to a particular player, from 0..2
	 */
	OSCdef(\xy, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/xy');
	OSCdef(\in_lvl, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/in_lvl');
	OSCdef(\out_lvl, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/out_lvl');
	OSCdef(\str_lvl, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/str_lvl');
	OSCdef(\rec, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/rec');
	OSCdef(\stop, {|msg, time, addr, recvPort|
		var tgt = msg[1];
		if (tgt >= 0 && tgt <= 2, {
		});
	},'/stop');

});
)

(

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

a = [1, 2, 3]

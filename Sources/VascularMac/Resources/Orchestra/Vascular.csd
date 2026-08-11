<CsoundSynthesizer>
<CsOptions>
; Vascular embeds Csound as a DSP library. AVAudioEngine owns the device clock,
; and score events arrive through csoundInputMessageAsync.
-n -d -m0
</CsOptions>
<CsInstruments>
sr = 48000
ksmps = 32
nchnls = 2
0dbfs = 1

giSine ftgen 1, 0, 16384, 10, 1
giSaw ftgen 2, 0, 16384, 7, 1, 16384, -1
giWindow ftgen 3, 0, 16384, 20, 2, 1
giNoiseIR ftgen 4, 0, 4096, 21, 6, 0.018

; Eight tracks × seven processors require fewer than 128 live audio buses.
; A modest reserve supports crossfades and rapid edits without continuously
; clearing thousands of unused vectors on every control cycle.
zakinit 256, 1
gaMasterL init 0
gaMasterR init 0
gkTrackVolume[] fillarray 1, 1, 1, 1, 1, 1, 1, 1
gkTrackPan[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackReverb[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackDelay[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackSaturation[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackCrusher[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackGate[] fillarray 0, 0, 0, 0, 0, 0, 0, 0
gkTrackGateGain[] fillarray 1, 1, 1, 1, 1, 1, 1, 1
gkMasterTempo init 90
gkReverbSize init 0.5
gkReverbDecay init 0.68
gkReverbTone init 0.53
gkReverbMotion init 0.15
gkDelayTime init 0.4
gkDelayFeedback init 0.52
gkDelayTone init 0.55
gkDelayWidth init 0.45
gkSaturationDrive init 0.38
gkSaturationCurve init 0.3
gkSaturationTone init 0.58
gkSaturationBody init 0.35
gkCrusherBits init 0.2
gkCrusherRate init 0.4
gkCrusherJitter init 0.08
gkCrusherTone init 0.27
gaReverbL init 0
gaReverbR init 0
gaDelayL init 0
gaDelayR init 0
gaSaturationL init 0
gaSaturationR init 0
gaCrusherL init 0
gaCrusherR init 0

instr 10
    iTrack = 0
    while iTrack < 8 do
        gkTrackVolume[iTrack] = 1
        gkTrackPan[iTrack] = 0
        gkTrackReverb[iTrack] = 0
        gkTrackDelay[iTrack] = 0
        gkTrackSaturation[iTrack] = 0
        gkTrackCrusher[iTrack] = 0
        gkTrackGate[iTrack] = 0
        gkTrackGateGain[iTrack] = 1
        iTrack += 1
    od
endin

; Each track owns an independent aleatoric gate. Random decisions are renewed
; only on tempo-related boundaries: left of centre divides the master beat,
; right of centre multiplies it. Magnitude also controls depth; centre is off.
instr 600
    iTrack = p4
    kPosition portk gkTrackGate[iTrack], 0.12, 0
    kMagnitude = abs(kPosition)
    kExponent = int((kMagnitude * 3) + 0.5)
    kMultiplier = 1
    if kPosition < 0 then
        kMultiplier = 1 / pow(2, kExponent)
    elseif kPosition > 0 then
        kMultiplier = pow(2, kExponent)
    endif
    kRate = (gkMasterTempo / 60) * kMultiplier
    kDecision randomh 0, 1, kRate
    kThreshold randomh 0.28, 0.72, (kRate * 0.25) + 0.001
    kAccent randomh 0.72, 1, (kRate * 0.5) + 0.001
    kOpen = (kDecision > kThreshold ? kAccent : 0.04)
    kTarget = 1 + ((kOpen - 1) * kMagnitude)
    kSmoothed portk kTarget, 0.018, 1
    gkTrackGateGain[iTrack] = kSmoothed
endin

opcode VascularSource, a, iiiiii
    iFamily, iDepth, iSeed, iVariationSeed, iFundamental, iAuxiliary xin

    ; Independent, static characteristics give each source a different material
    ; identity without pitch sweeps or regular note-like sequencing.
    iTimbreCharacter = (iVariationSeed % 1013) / 1013
    iDensityCharacter = ((iVariationSeed / 1013) % 1019) / 1019
    iBrightness = ((iSeed / 1009) % 1021) / 1021
    ; A separate voicing draw prevents brightness from merely tracking density
    ; or decay. Its squared upper range intentionally creates occasional vivid,
    ; projecting acoustic models while preserving muted seeds.
    iPhysicalVoicing = ((iVariationSeed / 104729) % 1009) / 1009
    iPhysicalPresence = 0.18 + (iPhysicalVoicing * iPhysicalVoicing * 1.82)
    iBase = iFundamental
    ; Internal pitched components use a just-intonation subset so distinct
    ; synthesis families retain one harmonic interpretation of the session.
    iHarmonicA[] fillarray 1.125, 1.2, 1.25, 1.333333333, 1.5, 1.6, 1.666666667, 1.875
    iHarmonicB[] fillarray 2, 3, 4, 5, 6, 7, 8, 9
    iRatioA = iHarmonicA[iVariationSeed % 8]
    iRatioB = iHarmonicB[int(iVariationSeed / 8) % 8]

    ; Slow movement is intentionally microtonal, not a wandering pitch system.
    kDrift randomi -0.0035 * iBase, 0.0035 * iBase, 0.25 + (iDepth * 2.7)
    kScatter randomh 0.15, 1, 3 + (iDepth * 22)
    kPhase randomi 0, 1, 0.4 + (iDepth * 3)
    aNoise pinkish 0.16
    aDust dust2 0.24, 2 + (iDepth * 52)
    ; Sparse stochastic clocks do not guarantee an event near instrument start.
    ; This short, seeded-noise onset wakes impact and waveguide models
    ; immediately, then disappears before their irregular clocks take over.
    ; Its low sustain crosses the graph's click-safe fade without imposing a
    ; recurring beat or changing the model's long-term behaviour.
    aOnsetNoise rand 1
    aOnsetEnvelope linseg 1, 0.018, 0.2, 0.19, 0.13, 0.12, 0
    aOnsetExcitation = aOnsetNoise * aOnsetEnvelope

    if iFamily == 0 then
        aSource grain3 iBase * iRatioA, kPhase, \
            iBase * (0.008 + iDepth * 0.035), 0.7, \
            0.018 + (iDepth * (0.055 + iDensityCharacter * 0.1)), \
            6 + (iDepth * (31 + iDensityCharacter * 72)), 96, giSaw, giWindow, \
            -0.45, -0.7, iSeed + 1, 0
        aSource = aSource * 0.13
    elseif iFamily == 1 then
        ; Slowly breathing inharmonic residue, without a permanent noise bed.
        kR1 randomi 0.35, 1, 0.07 + iDensityCharacter * 0.31
        kR2 randomi 0.2, 0.9, 0.05 + iTimbreCharacter * 0.23
        aR1 poscil 0.055 * kR1, iBase, giSine
        aR2 poscil 0.042 * kR2, iBase * iRatioA, giSine
        aR3 poscil 0.032 * (1 - kR2 * 0.45), iBase * 2, giSine
        aR4 poscil 0.024 * (0.4 + kR1 * 0.6), iBase * iRatioB, giSine
        aSource = aR1 + aR2 + aR3 + aR4
    elseif iFamily == 2 then
        aModalExcitation = aDust + (aOnsetExcitation * 0.34)
        aR1 mode aModalExcitation, iBase, 35 + iBrightness * 45
        aR2 mode aModalExcitation, iBase * iRatioB, 70 + iTimbreCharacter * 90
        aR3 mode aModalExcitation, iBase * (iRatioB + 5), 130 + iDensityCharacter * 150
        aSource = (aModalExcitation * 0.25) + ((aR1 + aR2 + aR3) * 0.72)
    elseif iFamily == 3 then
        iFundamental = iBase
        ; A Poisson-like strike clock keeps the waveguide alive without imposing
        ; a meter. Density itself changes at irregular sample-and-hold intervals.
        kStrikeDensity randomh 0.15 + iDensityCharacter * 0.5, \
            1.4 + iDepth * (2.1 + iDensityCharacter * 5.2), \
            0.08 + iDepth * (0.22 + iTimbreCharacter * 0.52)
        aStrike dust2 1.08, kStrikeDensity
        aStrikeColour rand 0.65
        aExcitation = (aStrike * (1 + aStrikeColour)) + (aOnsetExcitation * 0.76)
        aBuffer delayr 0.08
        aString deltapi 1 / iFundamental
        aDamped tone aString, 1500 + iBrightness * 7200 + iDepth * 4300
        delayw tanh(aExcitation + aDamped * (0.935 + iDepth * 0.045))
        aSource = (aString * 0.62) + (aStrike * (0.06 + iPhysicalPresence * 0.025))
    elseif iFamily == 4 then
        aBow poscil 0.035, iBase * 0.5, giSine
        aExciter = (aBow * (0.55 + kScatter * 0.45)) + (aDust * 0.08)
        aBuffer delayr 0.8
        aFeedback deltapi (1 / iBase) * (1.2 + iDepth * (7 + iTimbreCharacter * 18))
        delayw tanh(aExciter + (aFeedback * (0.68 + iDepth * 0.24)))
        aSource = aFeedback * 0.42
    elseif iFamily == 5 then
        aCore gbuzz 0.085, iBase + kDrift, \
            7 + iBrightness * 19 + (iDepth * (13 + iDensityCharacter * 27)), 1, 0.91, giSine
        kRecursion randomi 1.2, 5 + (iDepth * 11), 0.08 + (iDepth * 2.2)
        aSource = tanh(aCore * kRecursion) * 0.28 + (aDust * 0.006)
    elseif iFamily == 6 then
        kHarmonics randomi 2, 18 + (iDepth * 46), 0.12 + (iDepth * 3.1)
        aPulsar gbuzz 0.075 * kScatter, iBase * iRatioA, \
            kHarmonics, 1, 0.92, giSine
        kPulsarGate randomh 0.05, 1, 5 + (iDepth * 48)
        aSource = aPulsar * kPulsarGate + (aDust * 0.008)
    elseif iFamily == 7 then
        kFMIndex randomi 0.4, 3 + (iDepth * 12), 0.07 + (iDepth * 2.9)
        aFMMod poscil iBase * kFMIndex, iBase * iRatioA, giSine
        aFM poscil 0.11, iBase + aFMMod, giSine
        aSource = aFM + (aNoise * 0.004)
    elseif iFamily == 8 then
        aTerrainX poscil 0.72, iBase + kDrift, giSine
        aTerrainY poscil 0.72, iBase * iRatioA - kDrift, giSaw
        kTerrain randomi 1.1, 4 + (iDepth * 8), 0.05 + (iDepth * 1.7)
        aSource = tanh((aTerrainX * aTerrainY + aTerrainX * 0.4) * kTerrain) * 0.14
    elseif iFamily == 9 then
        aC1 poscil 0.035, iBase, giSine
        aC2 poscil 0.028, iBase * iRatioA + kDrift, giSine
        aC3 poscil 0.025, iBase * 2 - kDrift, giSine
        aC4 poscil 0.021, iBase * iRatioB, giSine
        aC5 poscil 0.018, iBase * iRatioB, giSine
        aSource = (aC1 + aC2 + aC3 + aC4 + aC5) * (0.45 + kScatter * 0.55)
    elseif iFamily == 10 then
        kBandLife randomh 0.28, 1, 0.17 + iDepth * 1.1
        aB1 reson aNoise, iBase * 2, 90 + (iDepth * 310), 1
        aB2 reson aNoise, iBase * 7, 170 + (iDepth * 620), 1
        aSource = (aB1 + aB2) * (0.12 + kBandLife * 0.2)
    elseif iFamily == 11 then
        ; A continuous beating swarm; stochastic motion changes its internal
        ; balance without reducing every source to dust excitation.
        kSwarmA randomi 0.15, 1, 0.03 + iDensityCharacter * 0.22
        kSwarmB randomi 0.12, 0.9, 0.04 + iTimbreCharacter * 0.27
        aS1 poscil 0.042 * kSwarmA, iBase, giSine
        aS2 poscil 0.036 * kSwarmB, iBase * iRatioA, giSine
        aS3 poscil 0.028 * (1 - kSwarmA * 0.5), iBase * 2, giSine
        aS4 poscil 0.023 * (1 - kSwarmB * 0.45), iBase * iRatioB, giSine
        aS5 poscil 0.017, iBase * (iRatioB + 5), giSine
        aSource = aS1 + aS2 + aS3 + aS4 + aS5
    elseif iFamily == 12 then
        ; Karplus-Strong string choir. An unstable Poisson clock excites three
        ; independently damped waveguides, so the source remains alive without
        ; settling into a sequencer-like pulse.
        kKSRate randomh 0.18 + iDensityCharacter * 0.42, \
            1.05 + iDepth * (1.7 + iDensityCharacter * 2.8), \
            0.09 + iTimbreCharacter * 0.43
        aKSTrigger dust2 0.82, kKSRate
        aKSNoise rand 0.72
        aKSExcite = (aKSTrigger * aKSNoise) + (aOnsetExcitation * 0.74)
        aKSBuffer1 delayr 0.09
        aKSTap1 deltapi 1 / iBase
        aKSDamp1 tone aKSTap1, 2600 + iBrightness * 9300
        delayw aKSExcite + aKSDamp1 * (0.958 + iDepth * 0.026)
        aKSBuffer2 delayr 0.09
        aKSTap2 deltapi 1 / (iBase * iRatioA)
        aKSDamp2 tone aKSTap2, 1900 + iTimbreCharacter * 8100
        delayw aKSExcite * 0.72 + aKSDamp2 * (0.949 + iDepth * 0.03)
        aKSBuffer3 delayr 0.09
        aKSTap3 deltapi 1 / (iBase * 2)
        aKSDamp3 tone aKSTap3, 1450 + iDensityCharacter * 6900
        delayw aKSExcite * 0.48 + aKSDamp3 * (0.94 + iDepth * 0.034)
        aSource = (aKSTap1 * 0.43) + (aKSTap2 * 0.34) + (aKSTap3 * 0.25)
    elseif iFamily == 13 then
        ; Prepared string: a damped string fundamental coupled to asymmetric,
        ; inharmonic bridge/contact resonances.
        kPrepRate randomh 0.12, 2.2 + iDepth * 3.8, 0.13 + iDensityCharacter * 0.51
        aPrepHit dust2 0.72, kPrepRate
        aPrepNoise rand 0.58
        aPrepExcite = (aPrepHit * aPrepNoise) + (aOnsetExcitation * 0.66)
        aPrepBuffer delayr 0.09
        aPrepString deltapi 1 / iBase
        aPrepDamp tone aPrepString, 1850 + iBrightness * 7900
        delayw aPrepExcite + aPrepDamp * (0.948 + iDepth * 0.035)
        aPrepM1 mode aPrepExcite, iBase * 2.071, 90 + iDepth * 170
        aPrepM2 mode aPrepExcite, iBase * 3.917, 140 + iDepth * 270
        aPrepM3 mode aPrepExcite, iBase * 6.43, 210 + iDepth * 420
        aSource = (aPrepString * 0.42) + ((aPrepM1 + aPrepM2) * 0.48) \
            + (aPrepM3 * (0.42 + iPhysicalPresence * 0.12))
    elseif iFamily == 14 then
        ; Inharmonic metal plate, synthesized as an impact-driven modal body.
        kPlateRate randomh 0.08, 1.25 + iDepth * 2.4, 0.17 + iTimbreCharacter * 0.62
        aPlateHit dust2 0.65, kPlateRate
        aPlateNoise rand 0.68
        aPlateExcite = (aPlateHit * aPlateNoise) + (aOnsetExcitation * 0.7)
        aPlate1 mode aPlateExcite, iBase, 180 + iDepth * 520
        aPlate2 mode aPlateExcite, iBase * 1.593, 240 + iDepth * 760
        aPlate3 mode aPlateExcite, iBase * 2.136, 310 + iDepth * 980
        aPlate4 mode aPlateExcite, iBase * 2.917, 390 + iDepth * 1240
        aPlate5 mode aPlateExcite, iBase * 4.07, 480 + iDepth * 1580
        aSource = (aPlate1 * 0.52) + (aPlate2 * 0.43) + (aPlate3 * 0.38) \
            + (aPlate4 * (0.3 + iPhysicalPresence * 0.05)) \
            + (aPlate5 * (0.22 + iPhysicalPresence * 0.08))
    elseif iFamily == 15 then
        ; Circular membrane ratios retain pitch identity while making a clearly
        ; different, skin-like object with shorter high-frequency modes.
        kMemRate randomh 0.1, 1.8 + iDepth * 3.1, 0.11 + iDensityCharacter * 0.57
        aMemHit dust2 0.76, kMemRate
        aMemNoise rand 0.54
        aMemExcite = (aMemHit * aMemNoise) + (aOnsetExcitation * 0.64)
        aMem1 mode aMemExcite, iBase, 55 + iDepth * 110
        aMem2 mode aMemExcite, iBase * 1.594, 72 + iDepth * 145
        aMem3 mode aMemExcite, iBase * 2.136, 88 + iDepth * 185
        aMem4 mode aMemExcite, iBase * 2.296, 105 + iDepth * 220
        aMem5 mode aMemExcite, iBase * 2.653, 120 + iDepth * 260
        aSource = (aMem1 * 0.68) + (aMem2 * 0.49) + (aMem3 * 0.37) \
            + (aMem4 * (0.25 + iPhysicalPresence * 0.04)) \
            + (aMem5 * (0.2 + iPhysicalPresence * 0.06))
    elseif iFamily == 16 then
        ; Bowed resonant body. Slowly changing friction excites stable body
        ; modes; movement is in pressure/colour, never a laser-like pitch sweep.
        kBowPressure randomi 0.24, 0.86, 0.035 + iTimbreCharacter * 0.16
        kBowGrain randomh 0.45, 1, 0.7 + iDensityCharacter * 4.8
        aBowNoise pinkish 0.18
        aBowFriction = tanh(aBowNoise * (2.2 + kBowPressure * 5.5)) * kBowGrain
        aBow1 mode aBowFriction, iBase, 45 + iDepth * 95
        aBow2 mode aBowFriction, iBase * iRatioA, 75 + iDepth * 155
        aBow3 mode aBowFriction, iBase * 2, 110 + iDepth * 230
        aBow4 mode aBowFriction, iBase * 3, 145 + iDepth * 310
        aSource = (aBow1 * 0.48) + (aBow2 * 0.42) + (aBow3 * 0.32) \
            + (aBow4 * (0.22 + iPhysicalPresence * 0.07))
    elseif iFamily == 17 then
        ; Reed and bore model: nonlinear breath turbulence drives harmonic bore
        ; modes. The breath changes irregularly while resonant pitch stays fixed.
        kBreath randomi 0.22, 0.88, 0.045 + iDensityCharacter * 0.19
        kTongue randomh 0.35, 1, 0.45 + iTimbreCharacter * 4.2
        aReedNoise pinkish 0.16
        aReedDrive = tanh(aReedNoise * (2.5 + kBreath * 7)) * kTongue
        aReed1 mode aReedDrive, iBase, 38 + iDepth * 65
        aReed2 mode aReedDrive, iBase * 3, 65 + iDepth * 110
        aReed3 mode aReedDrive, iBase * 5, 92 + iDepth * 160
        aReed4 mode aReedDrive, iBase * 7, 125 + iDepth * 215
        aSource = (aReed1 * 0.5) + (aReed2 * 0.36) \
            + (aReed3 * (0.22 + iPhysicalPresence * 0.07)) \
            + (aReed4 * (0.15 + iPhysicalPresence * 0.08))
    elseif iFamily == 18 then
        ; Glass bowl: sparse soft strikes and very high-Q partials produce long,
        ; clean decays without requiring a downstream reverb.
        kGlassRate randomh 0.045, 0.7 + iDepth * 1.2, 0.19 + iTimbreCharacter * 0.71
        aGlassHit dust2 0.48, kGlassRate
        aGlassNoise rand 0.42
        aGlassExcite = (aGlassHit * aGlassNoise) + (aOnsetExcitation * 0.5)
        aGlass1 mode aGlassExcite, iBase * 2, 420 + iDepth * 1180
        aGlass2 mode aGlassExcite, iBase * 2.756, 560 + iDepth * 1540
        aGlass3 mode aGlassExcite, iBase * 5.404, 710 + iDepth * 2010
        aGlass4 mode aGlassExcite, iBase * 8.933, 880 + iDepth * 2480
        aSource = (aGlass1 * 0.58) + (aGlass2 * 0.47) \
            + (aGlass3 * (0.31 + iPhysicalPresence * 0.06)) \
            + (aGlass4 * (0.21 + iPhysicalPresence * 0.09))
    else
        ; Wooden cavity: irregular knocks excite compact, lossy resonances. This
        ; occupies the dry/organic end of the palette instead of another drone.
        kWoodRate randomh 0.14, 2.5 + iDepth * 4.3, 0.09 + iDensityCharacter * 0.48
        aWoodHit dust2 0.82, kWoodRate
        aWoodNoise rand 0.5
        aWoodExcite = (aWoodHit * aWoodNoise) + (aOnsetExcitation * 0.68)
        aWood1 mode aWoodExcite, iBase, 24 + iDepth * 48
        aWood2 mode aWoodExcite, iBase * 1.47, 31 + iDepth * 63
        aWood3 mode aWoodExcite, iBase * 2.09, 42 + iDepth * 82
        aWood4 mode aWoodExcite, iBase * 3.56, 58 + iDepth * 105
        aWoodBody tone aWoodExcite, 900 + iBrightness * 3600
        aSource = (aWood1 * 0.68) + (aWood2 * 0.48) + (aWood3 * 0.34) \
            + (aWood4 * (0.2 + iPhysicalPresence * 0.06)) + (aWoodBody * 0.085)
    endif

    ; Acoustic models receive bounded presence compensation before entering the
    ; processor graph. This is deliberately not RMS normalization: impact and
    ; decay dynamics remain intact, but their useful level and upper partials no
    ; longer disappear beside continuous oscillator families.
    if iFamily == 3 || iFamily >= 12 then
        ; Sparse excitations have much lower average energy than drones. The
        ; 2.2–3.4x range puts their bodies on an equal perceptual footing while
        ; the soft limiter catches only unusually coincident impacts.
        iAcousticGain = 2.08 + (iPhysicalPresence * 0.66)
        aPhysicalAir atone aSource, 620 + (iBrightness * 1380)
        aSource = (aSource * iAcousticGain) \
            + (aPhysicalAir * (0.22 + iPhysicalPresence * 0.42))
        aSource = tanh(aSource * 1.12) / 1.12
    endif

    if iAuxiliary == 1 then
        aAux vco2 0.045 * kScatter, iBase * 0.5 + kDrift, 12
        aAuxRing poscil 0.7, 0.13 + (iDepth * 8.3), giSine
        aSource = aSource + (aAux * aAuxRing)
    endif

    xout dcblock2(aSource)
endop

opcode VascularTransform, a, aiiii
    aInput, iKind, iDepth, iSeed, iFundamental xin
    iRate = 0.025 + ((iSeed % 97) / 97) * (0.35 + iDepth * 0.95)
    kSine lfo 1, iRate, 0
    kNoise randomi -1, 1, iRate * 0.61 + 0.03
    kStep randomh -1, 1, iRate * 1.7 + 0.07
    kMotion = (kSine * 0.5) + (kNoise * 0.3) + (kStep * 0.2)
    aOutput = aInput
    iProcessorRatios[] fillarray 1, 1.125, 1.2, 1.25, 1.333333333, 1.5, 1.666666667, 1.875
    iProcessorRatio = iProcessorRatios[iSeed % 8]

    if iKind == 0 then
        kCutoffTarget randomh 220, 1800 + iDepth * 5200, iRate * 0.7 + 0.04
        kCutoff portk kCutoffTarget, 0.035
        kBandwidth = kCutoff * (0.22 + abs(kStep) * 0.32)
        aLow butterlp aInput, kCutoff
        aBand reson aInput, kCutoff * 1.37, kBandwidth, 1
        aHigh butterhp aInput, 1200 + abs(kStep) * 3600
        aOutput = (aLow * 0.55) + (aBand * 0.42) + (aHigh * 0.24)
    elseif iKind == 1 then
        iJitter1 = 7 + (iSeed % 89)
        iJitter2 = 31 + (iSeed % 257)
        aGrain1 vdelay3 aInput, iJitter1, 500
        aGrain2 vdelay3 aInput, iJitter2, 500
        kGateTarget randomh 0.08, 0.92, 9 + iDepth * 37
        kGate portk kGateTarget, 0.018
        aOutput = (aGrain1 * kGate) + (aGrain2 * (1 - kGate))
    elseif iKind == 2 then
        iTapDelay = 45 + (iSeed % 421)
        iFeedbackDelay = 0.11 + ((iSeed % 503) / 503) * 0.72
        aTap vdelay3 aInput, iTapDelay, 750
        aBuffer delayr 1.6
        aFeedback deltapi iFeedbackDelay
        kFeedback = 0.43 + iDepth * 0.38 + kStep * 0.055
        delayw tanh(aInput + aTap * 0.28 + aFeedback * kFeedback)
        aOutput = (aTap * 0.48) + (aFeedback * 0.72)
    elseif iKind == 3 then
        kTime = 0.74 + abs(kSine) * (0.18 + iDepth * 0.075)
        kDamp = 1800 + abs(kNoise) * (5500 + iDepth * 10500)
        aVerbL, aVerbR reverbsc aInput, aInput * kStep, kTime, kDamp
        aOutput = (aVerbL + aVerbR) * 0.62
    elseif iKind == 4 then
        kFreezeGate = (kStep > (0.2 - iDepth * 0.35) ? 1 : 0)
        iRatios[] fillarray 0.5, 0.75, 1, 1.5, 2
        iRatio = iRatios[iSeed % 5]
        fAnalysis pvsanal aInput, 1024, 256, 1024, 1
        fFrozen pvsfreeze fAnalysis, kFreezeGate, kFreezeGate
        fShift pvscale fFrozen, iRatio
        aOutput pvsynth fShift
    elseif iKind == 5 then
        kDrive = 1.4 + (1 + kMotion) * (1.1 + iDepth * 5.2)
        aFold = tanh(aInput * kDrive)
        aShaped = sin(aFold * (1.05 + abs(kStep) * 2.6)) * 0.72
        aOutput tone aShaped, 3200 + abs(kNoise) * 5200
    elseif iKind == 6 then
        kDrive = 2.2 + abs(kSine) * (4.5 + iDepth * 14)
        aPositive = tanh(aInput * kDrive)
        aNegative = tanh(aInput * kDrive * (0.48 + abs(kNoise) * 0.42))
        aOutput = (aPositive * 0.62) + (aNegative * 0.28) + (aInput * 0.18)
        aOutput butterhp aOutput, 55 + (iSeed % 470)
        aOutput butterlp aOutput, 4200 + abs(kStep) * 5200
    elseif iKind == 7 then
        kInput downsamp aInput
        kBits = 7 + int((1 + kStep) * (1 + (1 - iDepth) * 2.2))
        kLevels = pow(2, kBits)
        kCrushed = int(kInput * kLevels) / kLevels
        aCrushed interp kCrushed
        aCrushed tone aCrushed, 4600 + abs(kNoise) * 4800
        aOutput = (aInput * 0.42) + (aCrushed * 0.58)
    elseif iKind == 8 then
        aConvolved ftconv aInput, giNoiseIR, 256, 0, 4096
        aOutput = aConvolved * (0.55 + abs(kMotion) * 1.6)
    elseif iKind == 9 then
        iR1 = iFundamental * iProcessorRatio
        iR2 = iFundamental * (2 + (iSeed % 4))
        iR3 = iFundamental * (6 + (iSeed % 7))
        kResonanceLife = 0.72 + kSine * 0.16 + kStep * 0.08
        aR1 mode aInput, iR1, 90 + iDepth * 280
        aR2 mode aInput, iR2, 160 + iDepth * 510
        aR3 mode aInput, iR3, 260 + iDepth * 840
        aOutput = (aR1 + aR2 + aR3) * kResonanceLife * 0.62
    elseif iKind == 10 then
        iRing = iFundamental * iProcessorRatio
        aMod poscil 1, iRing, giSine
        kRingLife = 0.68 + kSine * 0.17 + kStep * 0.1
        aOutput = aInput * (aMod * kRingLife + kStep * 0.18)
    elseif iKind == 11 then
        iD1 = 11 + (iSeed % 59)
        iD2 = 29 + (iSeed % 101)
        iD3 = 47 + (iSeed % 149)
        aD1 vdelay3 aInput, iD1, 100
        aD2 vdelay3 aD1, iD2, 150
        aD3 vdelay3 aD2, iD3, 220
        kDiffuseDamp = 4600 + abs(kNoise) * 4200
        aVerbL, aVerbR reverbsc aD3, -aD2, 0.82 + iDepth * 0.15, kDiffuseDamp
        aOutput = (aVerbL + aVerbR) * 0.58
    elseif iKind == 12 then
        iPhaseCentre = iFundamental * (3 + (iSeed % 9))
        kPhaseTarget randomh iPhaseCentre * 0.92, iPhaseCentre * 1.08, iRate * 0.4 + 0.03
        kPhase portk kPhaseTarget, 0.42
        kPhaseFeedback = 0.38 + iDepth * 0.28 + kSine * 0.04
        aOutput phaser1 aInput, kPhase, 4 + int(iDepth * 5), kPhaseFeedback
    elseif iKind == 13 then
        iFlangeCentre = 1 / (iFundamental * (2 + (iSeed % 7)))
        kFlangeTarget randomh iFlangeCentre * 0.94, iFlangeCentre * 1.06, iRate * 0.35 + 0.025
        kFlange portk kFlangeTarget, 0.31
        aFlangeDelay interp kFlange
        aOutput flanger aInput, aFlangeDelay, 0.28 + iDepth * 0.24
    else
        iFeedbackDelay = 0.045 + ((iSeed % 1301) / 1301) * 0.83
        aBuffer delayr 1.8
        aFeedback deltapi iFeedbackDelay
        kFeedbackLife = 0.63 + iDepth * 0.24 + kStep * 0.045
        delayw tanh(aInput * (1.2 + abs(kStep) * 2.1) + aFeedback * kFeedbackLife)
        aOutput = aFeedback
    endif

    ; `balance` can request extreme startup gain while a delay, FFT, or feedback
    ; processor is still filling. Explicit RMS matching has a hard gain ceiling,
    ; making graph construction incapable of producing a normalization burst.
    kInputRMS rms aInput
    kOutputRMS rms aOutput
    kGainTarget = kInputRMS / (kOutputRMS + 0.0005)
    kGainTarget limit kGainTarget, 0.12, 2.5
    kWetGain portk kGainTarget, 0.04, 1
    aWet = tanh(aOutput * kWetGain * 1.15) / 1.15
    if iKind == 5 || iKind == 6 || iKind == 7 then
        iDry = 0.38
    elseif iKind == 8 || iKind == 10 || iKind == 14 then
        iDry = 0.26
    elseif iKind == 4 || iKind == 9 then
        iDry = 0.2
    else
        iDry = 0.14
    endif
    xout dcblock2((aInput * iDry) + (aWet * (1 - iDry)))
endop

; A source exists only for a root vessel and remains alive as the graph grows.
instr 100
    iFamily = p4
    iDepth = p5
    iSeed = p6
    iVariationSeed = p7
    iFundamental = p8
    iOutputBus = p9
    aSource VascularSource iFamily, iDepth, iSeed, iVariationSeed, iFundamental, 0
    kEnvelope linsegr 0, 0.26, 1, 0.26, 0
    kSmooth = kEnvelope * kEnvelope * (3 - 2 * kEnvelope)
    kFade = sin(kSmooth * 1.5707963267948966)
    zawm aSource * kFade, iOutputBus
endin

; Every processor cell owns an independent instrument and modulation state.
; Kind -1 is a single graph edge. Multiple edges can mix into a processor's
; private inlet without an i-rate loop or a fixed fan-in ceiling.
instr 200
    iKind = p4
    if iKind < 0 then
        iInputBus = p5
        iOutputBus = p6
        aInput zar iInputBus
        zawm aInput, iOutputBus
    else
        iDepth = p5
        iSeed = p6
        iInputBus = p7
        iOutputBus = p8
        iFundamental = p9
        aInput zar iInputBus
        aProcessed VascularTransform dcblock2(aInput), iKind, iDepth, iSeed, iFundamental
        if iKind == 2 || iKind == 3 || iKind == 14 then
            iMorphTime = 0.9
        elseif iKind == 4 || iKind == 8 || iKind == 11 then
            iMorphTime = 0.48
        else
            iMorphTime = 0.26
        endif
        ; A new cell begins as a bounded dry wire and morphs toward its effect.
        ; Thus extending a chain cannot momentarily replace signal with an empty
        ; delay/reverb buffer or expose an uninitialised spectral processor.
        kMorph linseg 0, iMorphTime, 1
        aContinuous = (aInput * (1 - kMorph)) + (aProcessed * kMorph)
        kEnvelope linsegr 0, 0.2, 1, 0.2, 0
        kSmooth = kEnvelope * kEnvelope * (3 - 2 * kEnvelope)
        kLife = sin(kSmooth * 1.5707963267948966)
        zawm dcblock2(aContinuous) * kLife, iOutputBus
    endif
endin

; Mixer changes do not rebuild a graph. They update persistent per-track control
; channels which each terminal output follows through a short de-zippering ramp.
instr 700
    iTrack = p4
    gkTrackVolume[iTrack] = p5
    gkTrackPan[iTrack] = p6
    gkTrackReverb[iTrack] = p7
    gkTrackDelay[iTrack] = p8
    gkTrackSaturation[iTrack] = p9
    gkTrackCrusher[iTrack] = p10
    gkTrackGate[iTrack] = p11
endin

; Persistent master-return controls. Like the track mixer, these messages alter
; control channels only; the return instruments and their delay memory remain
; alive, so editing does not rebuild or abruptly clear an effect.
instr 710
    gkReverbSize = p4
    gkReverbDecay = p5
    gkReverbTone = p6
    gkReverbMotion = p7
    gkDelayTime = p8
    gkDelayFeedback = p9
    gkDelayTone = p10
    gkDelayWidth = p11
endin

instr 720
    gkSaturationDrive = p4
    gkSaturationCurve = p5
    gkSaturationTone = p6
    gkSaturationBody = p7
    gkCrusherBits = p8
    gkCrusherRate = p9
    gkCrusherJitter = p10
    gkCrusherTone = p11
endin

instr 800
    iInputBus = p4
    iTrack = p5
    iGain = p6
    aSignal zar iInputBus
    kVolume portk gkTrackVolume[iTrack], 0.12, 1
    kPanControl portk gkTrackPan[iTrack], 0.12, 0
    kReverb portk gkTrackReverb[iTrack], 0.12, 0
    kDelay portk gkTrackDelay[iTrack], 0.12, 0
    kSaturation portk gkTrackSaturation[iTrack], 0.12, 0
    kCrusher portk gkTrackCrusher[iTrack], 0.12, 0
    kGate portk gkTrackGateGain[iTrack], 0.012, 1
    kPan = (kPanControl + 1) * 0.5
    ; A smoothstep-driven sine law has zero slope at silence and unity while
    ; retaining complementary equal-power behavior between old and new paths.
    aEnvelope linsegr 0, 0.32, 1, 0.32, 0
    aSmooth = aEnvelope * aEnvelope * (3 - 2 * aEnvelope)
    aFade = sin(aSmooth * 1.5707963267948966)
    aSignal = tanh(aSignal * 1.4) * iGain * kVolume * kGate * aFade
    aTrackL = aSignal * sqrt(1 - kPan)
    aTrackR = aSignal * sqrt(kPan)
    vincr gaMasterL, aTrackL
    vincr gaMasterR, aTrackR
    vincr gaReverbL, aTrackL * kReverb
    vincr gaReverbR, aTrackR * kReverb
    vincr gaDelayL, aTrackL * kDelay
    vincr gaDelayR, aTrackR * kDelay
    vincr gaSaturationL, aTrackL * kSaturation
    vincr gaSaturationR, aTrackR * kSaturation
    vincr gaCrusherL, aTrackL * kCrusher
    vincr gaCrusherR, aTrackR * kCrusher
endin

instr 900
    ; Eight smoothed macros control the two shared stereo returns.
    kReverbSize portk gkReverbSize, 0.18, 0.5
    kReverbDecay portk gkReverbDecay, 0.18, 0.68
    kReverbTone portk gkReverbTone, 0.18, 0.53
    kReverbMotion portk gkReverbMotion, 0.24, 0.15
    ; A nonlinear upper range turns the return from a controllable room into a
    ; very long ambient instrument. Two decorrelated pre-diffusion paths feed a
    ; primary tank, which excites a slower secondary bloom tank.
    kRevPrimaryFeedback = 0.72 + (pow(kReverbDecay, 1.7) * 0.277)
    kRevBloomFeedback = 0.76 + (pow(kReverbDecay, 1.45) * 0.239)
    kRevCutoff = 1400 + (kReverbTone * 14600)
    kRevPreDelay = 3 + (kReverbSize * 105)
    kRevMotionA oscili kReverbMotion * 14, 0.025 + (kReverbMotion * 0.11), giSine
    kRevMotionB oscili kReverbMotion * 9, 0.017 + (kReverbMotion * 0.073), giSine, 0.37
    aRevDiffuseL1 vdelay3 gaReverbL, kRevPreDelay + kRevMotionA, 220
    aRevDiffuseR1 vdelay3 gaReverbR, kRevPreDelay - kRevMotionA, 220
    aRevCrossL = (gaReverbL * 0.68) + (gaReverbR * 0.32)
    aRevCrossR = (gaReverbR * 0.68) + (gaReverbL * 0.32)
    aRevDiffuseL2 vdelay3 aRevCrossL, (kRevPreDelay * 1.41) + 13 - kRevMotionB, 220
    aRevDiffuseR2 vdelay3 aRevCrossR, (kRevPreDelay * 1.57) + 7 + kRevMotionB, 220
    aRevFeedL = (aRevDiffuseL1 * 0.62) + (aRevDiffuseL2 * 0.52)
    aRevFeedR = (aRevDiffuseR1 * 0.62) + (aRevDiffuseR2 * 0.52)
    aRevPrimaryL, aRevPrimaryR reverbsc aRevFeedL, aRevFeedR, \
        kRevPrimaryFeedback, kRevCutoff
    aBloomFeedL = (aRevPrimaryL * 0.72) + (aRevPrimaryR * 0.28)
    aBloomFeedR = (aRevPrimaryR * 0.72) + (aRevPrimaryL * 0.28)
    aRevBloomL, aRevBloomR reverbsc aBloomFeedL, aBloomFeedR, \
        kRevBloomFeedback, kRevCutoff * 0.82
    kRevBloomMix = 0.1 + (kReverbSize * 0.28) + (kReverbDecay * 0.3)
    aReverbL = (aRevPrimaryL * 0.58) + (aRevBloomL * kRevBloomMix)
    aReverbR = (aRevPrimaryR * 0.58) + (aRevBloomR * kRevBloomMix)
    aRevMid = (aReverbL + aReverbR) * 0.5
    aRevSide = (aReverbL - aReverbR) * 0.5 * (0.55 + kReverbSize * 0.95)
    aReverbL = aRevMid + aRevSide
    aReverbR = aRevMid - aRevSide

    kDelayTimeControl portk gkDelayTime, 0.2, 0.4
    kDelayFeedbackControl portk gkDelayFeedback, 0.16, 0.52
    kDelayToneControl portk gkDelayTone, 0.16, 0.55
    kDelayWidthControl portk gkDelayWidth, 0.18, 0.45
    kDelayTimeL = 0.055 + (kDelayTimeControl * 0.895)
    kDelayTimeR = kDelayTimeL * (1 + kDelayWidthControl * 0.55)
    kDelayFeedback = 0.08 + (kDelayFeedbackControl * 0.64)
    kDelayCutoff = 1200 + (kDelayToneControl * 10800)
    aDelayBufferL delayr 1.6
    aDelayTapL deltapi kDelayTimeL
    aDelayFilteredL tone aDelayTapL, kDelayCutoff
    delayw gaDelayL + (aDelayFilteredL * kDelayFeedback)
    aDelayBufferR delayr 1.6
    aDelayTapR deltapi kDelayTimeR
    aDelayFilteredR tone aDelayTapR, kDelayCutoff
    delayw gaDelayR + (aDelayFilteredR * kDelayFeedback)
    aDelayMid = (aDelayFilteredL + aDelayFilteredR) * 0.5
    aDelaySide = (aDelayFilteredL - aDelayFilteredR) * 0.5 * (kDelayWidthControl * 1.5)
    aDelayOutL = aDelayMid + aDelaySide
    aDelayOutR = aDelayMid - aDelaySide

    kSatDriveControl portk gkSaturationDrive, 0.12, 0.38
    kSatCurve portk gkSaturationCurve, 0.12, 0.3
    kSatTone portk gkSaturationTone, 0.14, 0.58
    kSatBody portk gkSaturationBody, 0.14, 0.35
    kSatDrive = 1.2 + (kSatDriveControl * kSatDriveControl * 12.8)
    kSatCutoff = 900 + (kSatTone * 14100)
    aSatDrivenL = gaSaturationL * kSatDrive
    aSatDrivenR = gaSaturationR * kSatDrive
    aSatSoftL = tanh(aSatDrivenL)
    aSatSoftR = tanh(aSatDrivenR)
    aSatHardL = tanh(aSatDrivenL * 1.55)
    aSatHardR = tanh(aSatDrivenR * 1.55)
    aSatShapedL = (aSatSoftL * (1 - kSatCurve)) + (aSatHardL * kSatCurve)
    aSatShapedR = (aSatSoftR * (1 - kSatCurve)) + (aSatHardR * kSatCurve)
    aSatToneStageL tone dcblock2(aSatShapedL), kSatCutoff
    aSatToneStageR tone dcblock2(aSatShapedR), kSatCutoff
    aSatToneL tone aSatToneStageL, kSatCutoff
    aSatToneR tone aSatToneStageR, kSatCutoff
    aSatBodyL tone aSatToneL, 420 + (kSatBody * 1180)
    aSatBodyR tone aSatToneR, 420 + (kSatBody * 1180)
    kSatCompensation = 0.62 + (0.38 / (1 + kSatDriveControl * 1.8))
    aSaturationL = ((aSatToneL * (0.78 + kSatBody * 0.12)) \
        + (aSatBodyL * kSatBody * 0.48)) * kSatCompensation
    aSaturationR = ((aSatToneR * (0.78 + kSatBody * 0.12)) \
        + (aSatBodyR * kSatBody * 0.48)) * kSatCompensation

    kCrusherBitsControl portk gkCrusherBits, 0.12, 0.2
    kCrusherRateControl portk gkCrusherRate, 0.15, 0.4
    kCrusherJitterControl portk gkCrusherJitter, 0.18, 0.08
    kCrusherToneControl portk gkCrusherTone, 0.14, 0.27
    kCrusherBits = 3 + (kCrusherBitsControl * 13)
    kCrusherLevels = pow(2, kCrusherBits)
    kCrusherBaseRate = 250 * pow(96, kCrusherRateControl)
    kJitterL randomi -1, 1, 0.7 + (kCrusherJitterControl * 8.3)
    kJitterR randomi -1, 1, 0.83 + (kCrusherJitterControl * 7.7)
    kCrusherRateL = kCrusherBaseRate * pow(2, kJitterL * kCrusherJitterControl * 1.6)
    kCrusherRateR = kCrusherBaseRate * pow(2, kJitterR * kCrusherJitterControl * 1.6)
    aCrusherClockL mpulse 1, 1 / kCrusherRateL
    aCrusherClockR mpulse 1, 1 / kCrusherRateR
    aCrusherHeldL samphold gaCrusherL, aCrusherClockL
    aCrusherHeldR samphold gaCrusherR, aCrusherClockR
    aCrusherL = int(aCrusherHeldL * kCrusherLevels) / kCrusherLevels
    aCrusherR = int(aCrusherHeldR * kCrusherLevels) / kCrusherLevels
    kCrusherCutoff = 600 + (kCrusherToneControl * 13400)
    ; Rate-aware two-pole reconstruction keeps intentional decimation audible
    ; without turning each held-sample boundary into an unrelated full-scale click.
    kCrusherReconstruction = min(kCrusherCutoff, max(120, kCrusherBaseRate * 0.45))
    aCrusherSmoothL tone aCrusherL, kCrusherReconstruction
    aCrusherSmoothR tone aCrusherR, kCrusherReconstruction
    aCrusherL tone aCrusherSmoothL, kCrusherReconstruction
    aCrusherR tone aCrusherSmoothR, kCrusherReconstruction

    kRevReturnGain = 0.34 + (kReverbSize * 0.18) + (kReverbDecay * 0.16)
    aWetL = (aReverbL * kRevReturnGain) + (aDelayOutL * 0.52) \
        + (aSaturationL * 0.34) + (aCrusherL * 0.42)
    aWetR = (aReverbR * kRevReturnGain) + (aDelayOutR * 0.52) \
        + (aSaturationR * 0.34) + (aCrusherR * 0.42)
    aLeft = tanh((gaMasterL * 0.72) + aWetL)
    aRight = tanh((gaMasterR * 0.72) + aWetR)
    outs aLeft, aRight
    clear gaMasterL, gaMasterR, gaReverbL, gaReverbR, gaDelayL, gaDelayR, \
        gaSaturationL, gaSaturationR, gaCrusherL, gaCrusherR
endin

instr 950
    zacl 0, 255
endin
</CsInstruments>
<CsScore>
i 10 0 0.01
i 600 0 z 0
i 600 0 z 1
i 600 0 z 2
i 600 0 z 3
i 600 0 z 4
i 600 0 z 5
i 600 0 z 6
i 600 0 z 7
i 900 0 z
i 950 0 z
f 0 z
</CsScore>
</CsoundSynthesizer>

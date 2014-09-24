# -*- coding: utf-8 -*-
#
# Copyright (c) Tim Molteno 2013. tim@elec.ac.nz
import numpy as np
import math
import time
import scipy.signal


from tart.operation import observation
from tart.simulation import antennas
from tart.simulation import butter_filter


class Radio(object):
  def sampled_signal(ant_signal):
    raise 'Radio must implement a function filtered_signal that returns the '

class Max2769B(Radio):
  '''
    MAX2967B in preconfigured mode 2 has an IF center 4.092 MHz and a bandwidth of 2.5 MHz. The GPS L1 frequency is 1575.42 MHz
    The LO Frequency Range is from 1550 - 1610
    The reference division ratio is 16
    The main division ratio is 1536
    16.368 / 16 = 1.023
    1.023 * 1536 = 1571.328 - the local oscillator frequency
    1571.328 + 4.092  = 1575.42
    Thus mixing incoming L1 signal with the LO will give an IF of 4.092 MHz as required

    Note that Low Side Local Oscillator injection is used so image at 1567.236 MHz must be rejected

    Excerpts from the data sheet are as follows;
    .... including a dual-input LNA and mixer, FOLLOWED BY AN IMAGE REJECTED FILTER, PGA, VCO,
    fractional-N frequency synthesizer, crystal oscillator, and a multibit ADC.
    ... The MAX2769B completely eliminates the need for exter-nal IF filters by implementing on-chip monolithic filters
    ... Note 3: The LNA output connects to the mixer input without a SAW filter between them. (Case in default mode)
    The output of the LNA and the input of the mixer are brought off-chip to facilitate the use of a SAW filter.
  '''

  def __init__(self, sample_duration, noise_level, ref_freq = 16.368e6, freq_mult = 256, ref_div = 16, main_div = 1536, bandwidth = 2.5e6, order = 5):
    self.sample_duration = sample_duration
    self.ref_freq = ref_freq
    self.freq_mult = freq_mult
    self.ref_div = ref_div
    self.main_div = main_div
    self.bandwidth = bandwidth
    self.order = order
    self.noise_level = noise_level
    self.sampling_rate = self.ref_freq * self.freq_mult
    self.timebase = np.arange(0, self.sample_duration, 1.0/self.sampling_rate)
    self.baseband_timebase = np.arange(0, self.sample_duration, 1.0/self.ref_freq)
    self.int_freq = self.ref_freq / self.ref_div * 4
    # print self.int_freq

  def sampled_signal(self, ant_signal, ant_index, debug = False):
    t = np.linspace(0, self.sample_duration, len(ant_signal))

    # Produce the LO signal - massively oversampled so approximates continuous time
    lo_freq = self.ref_freq / self.ref_div * self.main_div  # LO frequency
    lo_omega = lo_freq*2*np.pi # LO in radians/s
    lo = np.sin(lo_omega*t) # Produce sinusoidal LO signal of reqd length

    if debug: print "LO Frequency: %f" % lo_freq
    if debug: print "Intermediate Frequency: %f" % self.int_freq

    # Mix the incoming signal with LO to generate the IF
    if_sig = lo * ant_signal
    if debug: print 'if_sig\n', if_sig

    # Need anti-aliasing filter BEFORE downsampling. See http://en.wikipedia.org/wiki/Downsampling
    # This is a low pass filter with a cutoff of ref_freq / 2.
    cutoff_freq = self.int_freq*1.5
    samp_rate=float(len(ant_signal)) / self.sample_duration

    # The Nyquist rate of the signal.
    nyq_rate = samp_rate / 2.0
    width = 2e6/nyq_rate

    # design filter
    b, a = scipy.signal.butter(3, cutoff_freq/nyq_rate)
    alias_sig = scipy.signal.lfilter(b, a, if_sig)

    # Decimate the signal data by a factor of freq_mult
    samp_sig = alias_sig[::self.freq_mult]
    if debug: print 'samp_sig\n', samp_sig

    if (self.noise_level[ant_index] > 0.0):
      noise = np.random.normal(0, self.noise_level[ant_index], samp_sig.size)
      samp_sig = samp_sig + noise

     #Implement 5th order Butterworth filter as used by the max2769B
    filt_sig = butter_filter.butter_bandpass_filter(samp_sig, self.int_freq-self.bandwidth/2, self.int_freq+self.bandwidth/2, self.ref_freq, self.order)
    if debug: print 'filt_sig\n', filt_sig

    # Convert the filtered and sampled signal to one bit NRZ binary format
    filt_sig1 = np.sign(filt_sig) # -1 if negative, 0 if 0, +1 if positive
    filt_sig1[filt_sig == 0] = 1 # Replace 0 with 1 - true NRZ
    if debug: print 'filt_sig1\n', filt_sig1

    return filt_sig1

  def get_full_obs(self, ant_sigs, utc_date, config):
    num_radio_samples = (len(self.timebase) / self.freq_mult) + 1
    # print num_radio_samples

    sampled_signals = np.zeros((config.num_antennas, num_radio_samples))

    for i in range(0, config.num_antennas):
      sampled_signals[i,:] = self.sampled_signal(ant_sigs[i], i)

    data = np.array(sampled_signals)

    obs = observation.Observation(utc_date, config, data=data)
    return obs


  def get_simplified_obs(self, baseband_signals, utc_date, config):
    num_samples = len(self.baseband_timebase)
    s_signals = []

    #if_sig = scipy.signal.hilbert(baseband_signals) * np.exp(2.0j * np.pi * (self.int_freq-self.bandwidth/2.) * self.baseband_timebase)
    if_sig = baseband_signals * np.sin(2.0 * np.pi * self.int_freq * self.baseband_timebase)

    for i in range(config.num_antennas):
      if (self.noise_level[i] > 0.0):
        # print i, self.noise_level[i]
        noise = np.random.normal(0., self.noise_level[i], len(if_sig[i]))
        if_sig[i] = if_sig[i] + noise

    for ant_num in range(0, config.num_antennas):
      #print 'ant_sig1\n', if_sig[ant_num, :]
      #####filt_sig = scipy.signal.lfilter(b, a, if_sig[ant_num])
      filt_sig1 = butter_filter.butter_bandpass_filter(if_sig[ant_num], self.int_freq-self.bandwidth/2., self.int_freq+self.bandwidth/2., self.ref_freq, self.order)
      s_signals.append(filt_sig1)
      #print 'filt_sig1\n', filt_sig.astype(float)

    # print s_signals
    s_signals = np.array(s_signals).real
    sampled_signals = np.sign(s_signals) # -1 if negative, 0 if 0, +1 if positive
    sampled_signals[s_signals == 0.0] = 1. # Replace 0 with 1 - true NRZ
    # sampled_signals = s_signals
    obs = observation.Observation(utc_date, config, data=sampled_signals)
    return obs







if __name__ == '__main__':
    import numpy as np
    import datetime
    import matplotlib.pyplot as plt

    from tart.operation import settings
    from tart.simulation import simulation_source
    from tart.simulation import antennas
    from tart.simulation import spectrum
    from tart.imaging import antenna_model
    from tart.util import angle

    from tart.simulation.radio import *

    config = settings.Settings('../test/test_telescope_config.json')
    # noiselvls =  0.1.*np.ones(config.num_antennas)
    noiselvls =  0.1 * np.ones(config.num_antennas)
    rad = Max2769B(sample_duration = 1.0e-3, noise_level = noiselvls)
    sources = [simulation_source.SimulationSource(amplitude = 1.0, azimuth = angle.from_dms(0.), elevation = angle.from_dms(90.), sample_duration = rad.sample_duration)]
    ants = [antennas.Antenna(config.get_loc(), pos) for pos in config.ant_positions]
    ant_models = [antenna_model.GpsPatchAntenna() for i in range(config.num_antennas)]
    utc_date = datetime.datetime.utcnow()


    plt.figure()
    ant_sigs = antennas.antennas_signal(ants, ant_models, sources, rad.timebase)
    rad_sig_full = rad.sampled_signal(ant_sigs[0, :], 0)
    obs_full = rad.get_full_obs(ant_sigs, utc_date, config)

    ant_sigs_simp = antennas.antennas_simplified_signal(ants, ant_models, sources, rad.baseband_timebase, rad.int_freq)
    obs_simp = rad.get_simplified_obs(ant_sigs_simp, utc_date, config)


    freqs, spec_full_before_obs = spectrum.plotSpectrum(rad_sig_full, rad.ref_freq, label='full_before_obs_obj', c='blue')
    freqs, spec_full = spectrum.plotSpectrum(obs_full.get_antenna(1), rad.ref_freq, label='full', c='cyan')
    freqs, spec_simp = spectrum.plotSpectrum(obs_simp.get_antenna(1), rad.ref_freq, label='simp', c='red')
    plt.legend()
    plt.show()

    # assertTrue((spec_full_before_obs == spec_full).all(), True)



    # plt.figure()
    # plt.plot(freqs, (spec_simp-spec_full)/spec_full)

    print len(obs_full.get_antenna(1)), obs_full.get_antenna(1).mean()
    print len(obs_simp.get_antenna(1)), obs_simp.get_antenna(1).mean()

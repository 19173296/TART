#
# Max Scheel (2018)
# max@max.ac.nz
#
# About:
#    Simple script demonstrate how to extract raw data samples for each antenna.
#
# Requires:
#   - tart python package to be installed (sudo pip install tart)
#   - raw data HDF file from the telescope
#
#
# Usage:
#   python time_sampled_signals.py --file ~/data/23_36_51.819267_data.pkl

from tart.operation import observation
import argparse

if __name__ == '__main__':
    PARSER = argparse.ArgumentParser(description='Acquire data from the TART telescope.')
    PARSER.add_argument('--file', required=True, help="The raw data data file ")

    ARGS = PARSER.parse_args()
    # Load the Observation file
    obs = observation.Observation_Load(ARGS.file)
    # Antennas are indexed from 0..23. Get the samples first one.
    samples_ant_0 = obs.get_antenna(0)
    print(samples_ant_0)

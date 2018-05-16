"""
The following code builds an Audulus wavetable node given a single cycle waveform.

The way it works is by building a spline node corresponding to the waveform, then
building the support patch to drive a Phasor node at the desired frequency into the
spline node to generate the output.

The complexity in the patch comes from the fact that for any wavetable you will
quickly reach a point where you are generating harmonics that are beyond the Nyquist
limit. Without diving into details, the problem with this is that it will cause
aliasing, or frequencies that are not actually part of the underlying waveform.
These usually sound bad and one usually doesn't want them.

The solution is as follows (glossing over important details):
1. determine a set of frequency bands we care about. In my case, 0-55Hz, and up by
   octaves for 8 octaves
2. for each frequency band, run the waveform through a Fast Fourier Transform
3. attenuate frequencies higher than the Nyquist limit for that frequency band
4. run an inverse FFT to get a new waveform
5. generate a wavetable for each frequency band
6. generate support patch to make sure the right wavetable is chosen for a given
   frequency

Steps 2–4 behave like a very precise single-pole non-resonant low-pass-filter, and
I probably could have used that, but this approach was more direct.
"""

require 'json'

# Load the library for building Audulus patches programmatically.
require_relative 'audulus'
require_relative 'sox'
require_relative 'wavetable_patch'
require_relative 'spline_patch'
require_relative 'spline_helper'


def build_patch_data(path)
  # break the path into directory and path so we can build the audulus file's name
  parent, file = path.split("/")[-2..-1]

  # load the samples from the WAV file
  samples = Sox.load_samples(path)

  # build the audulus patch name from the WAV file name
  basename = File.basename(file, ".wav")
  puts "building #{basename}.audulus"
  audulus_patch_name = "#{basename}.audulus"

  { :output_path => audulus_patch_name,
    :samples => samples,
    :title1 => parent,
    :title2 => basename,
  }
end

# Given a set of samples, build the Audulus wavetable node
def build_patch_from_samples(samples, title1, title2, output_path)
  puts "building #{output_path}"
  File.write(output_path, JSON.generate(Audulus.make_subpatch(WavetablePatch.build_patch(samples, title1, title2)['patch'])))
end

require 'optparse'

def parse_arguments!(argv)
  results = {
    :spline_only => false
  }
  option_parser = OptionParser.new do |opts|
    opts.banner = "build_audulus_wavetable_node [OPTIONS] WAV_FILE"

    opts.on("-h", "--help", "Prints this help") do
      results[:help] = opts.help
    end

    opts.on("-s", "--spline-only", "generate a patch containing only a spline corresponding to the samples in the provided WAV file") do
      results[:spline_only] = true
    end
  end

  option_parser.parse!(argv)
  if argv.count != 1
    results = {
      :help => option_parser.help
    }
  end

  results[:input_filename] = argv[0]

  results
end

def command(argv)
  arguments = argv.dup
  options = parse_arguments!(arguments)
  if options.has_key?(:help)
    puts options[:help]
    exit(0)
  end

  path = options[:input_filename]
  unless File.exist?(path)
    puts "Cannot find WAV file at #{path}"
    exit(1)
  end

  if options[:spline_only]
    SplinePatch.build_patch_from_wav_file(path)
  else
    WavetablePatch.build_patch_from_wav_file(path)
  end
end

# This code is the starting point.. if we run this file as
# its own program, do the following
if __FILE__ == $0
  command(ARGV)
end

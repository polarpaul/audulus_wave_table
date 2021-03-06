# The following code builds an Audulus wavetable node given a single cycle waveform.
#
# The way it works is by building a spline node corresponding to the waveform, then
# building the support patch to drive a Phasor node at the desired frequency into the
# spline node to generate the output.
#
# The complexity in the patch comes from the fact that for any wavetable you will
# quickly reach a point where you are generating harmonics that are beyond the Nyquist
# limit. Without diving into details, the problem with this is that it will cause
# aliasing, or frequencies that are not actually part of the underlying waveform.
# These usually sound bad and one usually doesn't want them.
#
# The solution is as follows (glossing over important details):
# 1. determine a set of frequency bands we care about. In my case, 0-55Hz, and up by
   # octaves for 8 octaves
# 2. for each frequency band, run the waveform through a Fast Fourier Transform
# 3. attenuate frequencies higher than the Nyquist limit for that frequency band
# 4. run an inverse FFT to get a new waveform
# 5. generate a wavetable for each frequency band
# 6. generate support patch to make sure the right wavetable is chosen for a given
   # frequency
#
# Steps 2–4 behave like a very precise single-pole non-resonant low-pass-filter, and
# I probably could have used that, but this approach was more direct.

require_relative 'antialias'

class WavetablePatch
  class <<self
    include Audulus
  end

  # Take a list of samples corresponding to a single cycle wave form
  # and generate an Audulus patch with a single wavetable node that
  # has title1 and title2 as title and subtitle
  def self.build_patch_helper(samples, title1, title2)
    # The below code lays out the Audulus nodes as needed to build
    # the patch. It should mostly be familiar to anyone who's built
    # an Audulus patch by hand.
    doc = build_init_doc
    patch = doc['patch']

    title1_node = build_text_node(title1)
    move_node(title1_node, -700, 300)
    expose_node(title1_node, -10, -30)

    add_node(patch, title1_node)

    title2_node = build_text_node(title2)
    move_node(title2_node, -700, 250)
    expose_node(title2_node, -10, -45)

    add_node(patch, title2_node)

    o_input_node = build_input_node
    o_input_node['name'] = ''
    move_node(o_input_node, -700, 0)
    expose_node(o_input_node, 0, 0)
    add_node(patch, o_input_node)

    o2hz_node = build_o2hz_node
    move_node(o2hz_node, -700, -100)
    add_node(patch, o2hz_node)

    wire_output_to_input(patch, o_input_node, 0, o2hz_node, 0)

    hertz_node = build_expr_node('clamp(hz, 0.0001, 12000)')
    move_node(hertz_node, -700, -200)
    add_node(patch, hertz_node)

    wire_output_to_input(patch, o2hz_node, 0, hertz_node, 0)

    phaser_node = build_simple_node('Phasor')
    move_node(phaser_node, -500, 0)
    add_node(patch, phaser_node)

    wire_output_to_input(patch, hertz_node, 0, phaser_node, 0)

    domain_scale_node = build_expr_node('x/2/pi')
    move_node(domain_scale_node, -300, 0)
    add_node(patch, domain_scale_node)

    wire_output_to_input(patch, phaser_node, 0, domain_scale_node, 0)

    # for each frequency band, resample using the method outlined above
    frequencies = (0..7).map {|i| 55*2**i}
    sample_sets = frequencies.map {|frequency|
      Antialias.antialias_for_fundamental(44100, frequency, samples)
    }

    # normalize the samples
    normalization_factor = 1.0 / sample_sets.flatten.map(&:abs).max
    normalized_sample_sets = sample_sets.map {|sample_set|
      sample_set.map {|sample| sample*normalization_factor}
    }

    # generate the actual spline nodes corresponding to each wavetable
    spline_nodes =
      normalized_sample_sets.each_with_index.map {|sample_set, i|
        scaled_samples = sample_set.map {|sample| (sample.to_f + 1.0)/2.0}
        spline_node = SplineHelper.build_spline_node_from_samples(scaled_samples)
        move_node(spline_node, -100, i*200)
        spline_node
      }

    add_nodes(patch, spline_nodes)

    spline_nodes.each do |spline_node|
      wire_output_to_input(patch, domain_scale_node, 0, spline_node, 0)
    end

    # generate the "picker," the node that determines which wavetable
    # to used based on the desired output frequency
    spline_picker_node = build_expr_node("clamp(log2(hz/55), 0, 8)")
    move_node(spline_picker_node, -100, -100)
    add_node(patch, spline_picker_node)

    mux_node = build_xmux_node
    move_node(mux_node, 400, 0)
    add_node(patch, mux_node)

    spline_nodes.each_with_index do |spline_node, i|
      wire_output_to_input(patch, spline_node, 0, mux_node, i+1)
    end

    wire_output_to_input(patch, hertz_node, 0, spline_picker_node, 0)
    wire_output_to_input(patch, spline_picker_node, 0, mux_node, 0)

    range_scale_node = build_expr_node('x*2-1')
    move_node(range_scale_node, 600, 0)
    add_node(patch, range_scale_node)

    wire_output_to_input(patch, mux_node, 0, range_scale_node, 0)

    output_node = build_output_node
    output_node['name'] = ''
    move_node(output_node, 1100, 0)
    expose_node(output_node, 50, 0)
    add_node(patch, output_node)

    wire_output_to_input(patch, range_scale_node, 0, output_node, 0)

    doc
  end

  # Given a path to a single-cycle-waveform wav file, generate an Audulus wavetable
  # node
  def self.build_patch(patch_data)
    # build the patch as a full patch
    base_patch = build_patch_helper(patch_data[:samples], patch_data[:title], patch_data[:subtitle])['patch']

    # wrap it up as a subpatch
    final_patch = Audulus.make_subpatch(base_patch)

    # write the patch to a file as JSON (the format Audulus uses)
    File.write(patch_data[:output_path], JSON.generate(final_patch))
  end

end

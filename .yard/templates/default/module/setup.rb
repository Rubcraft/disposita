# frozen_string_literal: true

# YARD 0.9.45's default/module/setup.rb renders its special dynamic-method
# section without running the visibility/API verifier. Standard @api private,
# @private, private visibility, --hide-api, --no-private and --query therefore
# still expose method_missing there, even when it is absent from method lists.
# Apply the same verifier used by normal sections so API marked private stays
# out of public HTML (including RubyDoc-style output). This changes only docs.
# Remove this override once upstream applies its verifier to this section.
def methodmissing
  methods = object.meths(inherited: true, included: true)
  @mm = run_verifier(methods).find { |method| method.name == :method_missing && method.scope == :instance }
  erb(:methodmissing) if @mm
end

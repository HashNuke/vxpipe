defimpl Inspect, for: Vxpipe.Calls.IssuedApiKey do
  import Inspect.Algebra

  def inspect(key, options) do
    fields = [
      id: key.id,
      tenant_key: key.tenant_key,
      name: key.name,
      scopes: key.scopes,
      secret: "[REDACTED]"
    ]

    concat(["#Vxpipe.Calls.IssuedApiKey<", to_doc(fields, options), ">"])
  end
end

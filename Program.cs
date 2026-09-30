using Newtonsoft.Json;
using Serilog;

// Tiny app that touches each dependency so they are real, used components.
Log.Logger = new LoggerConfiguration().WriteTo.Console().CreateLogger();

var name = args.Length > 0 ? args[0] : "SBOM Scanner";
var payload = new { message = $"Hello, {name}!" };

Log.Information("Newtonsoft: {Json}", JsonConvert.SerializeObject(payload));
Log.Information("System.Text.Json: {Json}", System.Text.Json.JsonSerializer.Serialize(payload));

using var http = new HttpClient();
Log.Information("HttpClient ready, timeout {Timeout}", http.Timeout);

Log.CloseAndFlush();

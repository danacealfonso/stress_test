import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const StressTestApp());
}

class StressTestApp extends StatelessWidget {
  const StressTestApp({super.key});

  Future<Widget> _decideStartPage() async {
    if (Session.isLoggedIn) {
      return StressTestPage(domain: Session.domain!, token: Session.token!);
    }
    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<Widget>(
        future: _decideStartPage(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data!;
        },
      ),
    );
  }
}

/// ---------------- LOGIN PAGE ----------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _domainController = TextEditingController(
    text: "https://ccicqa-api.codyph.link/api/v1/auth/email/login",
  );
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool loading = false;
  String? error;

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });

    final domain = _domainController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final response = await http.post(
        Uri.parse(domain),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": username, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data["token"];
        if (token == null) {
          setState(() {
            error = "No token found in response.";
            loading = false;
          });
          return;
        }

        // Save to memory only
        Session.token = token;
        Session.domain = domain;

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StressTestPage(domain: domain, token: token),
          ),
        );
      } else {
        setState(() {
          error = "Login failed: ${response.statusCode}";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = "Error: $e";
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print("Seamless, fluent UI. Native speed. Built with WebAssembly.");
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 400,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildTextField("Domain", _domainController),
                      _buildTextField("Email", _usernameController),
                      _buildTextField("Password", _passwordController, obscure: true),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: loading ? null : _login,
                        child: loading ? const CircularProgressIndicator() : const Text("Login"),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 20),
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      ],
                      InkWell(
                        child: const Text("⬇️ Download macOS App"),
                        onTap: () {
                          launchUrl(Uri.parse("/downloads/stress_test.zip"));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}

/// ---------------- STRESS TEST PAGE ----------------
class StressTestPage extends StatefulWidget {
  final String domain;
  final String token;

  const StressTestPage({super.key, required this.domain, required this.token});

  @override
  State<StressTestPage> createState() => _StressTestPageState();
}

class _StressTestPageState extends State<StressTestPage> {
  final TextEditingController _endpointController = TextEditingController(
    text: "https://ccicqa-api.codyph.link/api/v1/mobiles/locations",
  );
  final TextEditingController _payloadController = TextEditingController(
    text: '{"user_id": "313484","lat": 10.3138596,"lon": 123.8945283}',
  );
  final TextEditingController _requestsController = TextEditingController(text: "100");
  final TextEditingController _concurrencyController = TextEditingController(text: "10");

  String _method = "POST";
  int successCount = 0;
  int failCount = 0;
  bool running = false;
  String log = "";

  final List<int> responseTimes = []; // ms per request
  bool _cancelled = false;

  // ---------------- START STRESS TEST ----------------
  Future<void> _startStressTest() async {
    final String url = _endpointController.text.trim();
    int totalRequests = int.tryParse(_requestsController.text) ?? 100;
    int concurrency = int.tryParse(_concurrencyController.text) ?? 10;

    Map<String, String> headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${widget.token}",
    };

    dynamic payload;
    try {
      payload = _payloadController.text.isNotEmpty ? jsonDecode(_payloadController.text) : {};
    } catch (_) {
      setState(() => log += "⚠️ Invalid JSON payload\n");
      return;
    }

    setState(() {
      running = true;
      _cancelled = false;
      successCount = 0;
      failCount = 0;
      responseTimes.clear();
      log = "🚀 Starting $_method stress test...\n";
    });

    for (int i = 0; i < totalRequests && !_cancelled; i += concurrency) {
      final chunkSize = (i + concurrency > totalRequests) ? (totalRequests - i) : concurrency;
      final chunk = List.generate(chunkSize, (j) => _sendRequest(url, headers, payload, i + j));
      await Future.wait(chunk);
    }

    setState(() {
      running = false;
      log += "✅ Done!\n";
      _appendLatencySummary();
    });
  }

  // ---------------- SEND REQUEST ----------------
  Future<void> _sendRequest(
    String url,
    Map<String, String> headers,
    dynamic payload,
    int id,
  ) async {
    final start = DateTime.now();
    try {
      late http.Response response;

      switch (_method) {
        case "GET":
          response = await http.get(Uri.parse(url), headers: headers);
          break;
        case "POST":
          response = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(payload));
          break;
        case "PUT":
          response = await http.put(Uri.parse(url), headers: headers, body: jsonEncode(payload));
          break;
        case "DELETE":
          response = await http.delete(Uri.parse(url), headers: headers);
          break;
        default:
          throw Exception("Unsupported method: $_method");
      }

      final latency = DateTime.now().difference(start).inMilliseconds;
      setState(() => responseTimes.add(latency));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() => successCount++);
      } else {
        setState(() {
          failCount++;
          log += "❌ Request $id failed: ${response.statusCode}\n";
        });
      }
    } catch (e) {
      final latency = DateTime.now().difference(start).inMilliseconds;
      setState(() {
        responseTimes.add(latency);
        failCount++;
        log += "⚠️ Request $id error: $e\n";
      });
    }
  }

  // ---------------- LATENCY SUMMARY ----------------
  void _appendLatencySummary() {
    if (responseTimes.isEmpty) return;

    final sorted = [...responseTimes]..sort();
    final avg = sorted.reduce((a, b) => a + b) / sorted.length;
    final p95 = sorted[(sorted.length * 0.95).floor()];
    final p99 = sorted[(sorted.length * 0.99).floor()];

    log += "📊 Latency summary:\n";
    log += "- Avg: ${avg.toStringAsFixed(2)} ms\n";
    log += "- P95: $p95 ms\n";
    log += "- P99: $p99 ms\n";
  }

  // ---------------- LATENCY LINE CHART ----------------
  Widget _buildLatencyLineChart() {
    if (responseTimes.isEmpty) {
      return const Text("📉 No data yet");
    }

    final spots = responseTimes
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
        .toList();

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.2)),
            ),
          ],
          titlesData: FlTitlesData(show: true),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  // ---------------- LATENCY HISTOGRAM ----------------
  Widget _buildLatencyHistogram() {
    if (responseTimes.isEmpty) {
      return const Text("📉 No data yet");
    }

    final buckets = <int, int>{};
    for (var t in responseTimes) {
      final bucket = (t ~/ 100) * 100; // bucket in 100ms intervals
      buckets[bucket] = (buckets[bucket] ?? 0) + 1;
    }

    final spots = buckets.entries
        .map(
          (e) => BarChartGroupData(
            x: e.key,
            barRods: [BarChartRodData(toY: e.value.toDouble(), color: Colors.green)],
          ),
        )
        .toList();

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          barGroups: spots,
          titlesData: FlTitlesData(show: true),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("API Stress Tester"),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: "Logout"),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: left (controls) + right (log window)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side (inputs and settings)
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Domain: ${widget.domain}"),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              const Text("Method: "),
                              const SizedBox(width: 10),
                              DropdownButton<String>(
                                value: _method,
                                items: [
                                  "GET",
                                  "POST",
                                  "PUT",
                                  "DELETE",
                                ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _method = val);
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          _buildTextField("Endpoint URL", _endpointController),
                          if (_method != "GET" && _method != "DELETE")
                            _buildTextField("Payload (JSON)", _payloadController, maxLines: 4),

                          Row(
                            children: [
                              Flexible(child: _buildTextField("Requests", _requestsController)),
                              const SizedBox(width: 10),
                              Flexible(
                                child: _buildTextField("Concurrency", _concurrencyController),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right side (log window)
                    Flexible(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("📜 Log:"),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            height: 300,
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SingleChildScrollView(child: Text(log)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Success/Fail counters
              Text("✅ Success: $successCount | ❌ Fail: $failCount"),

              const SizedBox(height: 20),

              // Control buttons
              Row(
                children: [
                  ElevatedButton(
                    onPressed: running ? null : _startStressTest,
                    child: Text("Start $_method Stress Test"),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: running ? () => setState(() => _cancelled = true) : null,
                    child: const Text("Stop Test"),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Text("📊 Latency Trend (ms):"),
              _buildLatencyLineChart(),
              const SizedBox(height: 20),
              const Text("📊 Latency Histogram (100ms buckets):"),
              _buildLatencyHistogram(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Future<void> _logout() async {
    Session.clear();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }
}

class Session {
  static String? token;
  static String? domain;

  static bool get isLoggedIn => token != null && domain != null;

  static void clear() {
    token = null;
    domain = null;
  }
}

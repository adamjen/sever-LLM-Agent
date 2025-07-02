{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "void",
        "body": [
          {
            "let": {
              "name": "response_times",
              "value": {
                "array": [
                  {"literal": 120.0},
                  {"literal": 110.0},
                  {"literal": 125.0},
                  {"literal": 115.0},
                  {"literal": 118.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "error_counts",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0},
                  {"literal": 2.0},
                  {"literal": 1.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "normal_response_time",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"literal": 120.0},
                    {"literal": 10.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "normal_error_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 2.0},
                    {"literal": 0.5}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "incident_probability",
              "type": "f64",
              "value": {"literal": 0.1}
            }
          },
          {
            "let": {
              "name": "is_incident",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "incident_probability"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "latency_spike_factor",
              "type": "f64",
              "value": {"literal": 3.0}
            }
          },
          {
            "let": {
              "name": "error_spike_factor",
              "type": "f64",
              "value": {"literal": 10.0}
            }
          },
          {
            "let": {
              "name": "current_response_time_mean",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "normal_response_time"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "is_incident"},
                          {"var": "latency_spike_factor"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "current_error_rate",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "normal_error_rate"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "is_incident"},
                          {"var": "error_spike_factor"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "observed_response_time",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"var": "current_response_time_mean"},
                    {"literal": 15.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "observed_errors",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"var": "current_error_rate"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "baseline_response_time",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "response_times"},
                  "index": {"literal": 0}
                }
              }
            }
          },
          {
            "let": {
              "name": "baseline_errors",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "error_counts"},
                  "index": {"literal": 0}
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "baseline_response_time"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "baseline_errors"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_incident"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_response_time"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_errors"}]
              }
            }
          }
        ]
      }
    }
  }
}
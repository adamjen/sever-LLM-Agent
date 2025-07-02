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
              "name": "historical_errors",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0},
                  {"literal": 15.0},
                  {"literal": 18.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "baseline_error_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 2.0},
                    {"literal": 1.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "changepoint_probability",
              "type": "f64",
              "value": {"literal": 0.15}
            }
          },
          {
            "let": {
              "name": "incident_detected",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "changepoint_probability"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "incident_severity_multiplier",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "lognormal",
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
              "name": "current_error_rate",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "baseline_error_rate"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "incident_detected"},
                          {"var": "incident_severity_multiplier"}
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
              "name": "predicted_current_errors",
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
              "name": "observed_recent_errors",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "historical_errors"},
                  "index": {"literal": 4}
                }
              }
            }
          },
          {
            "let": {
              "name": "should_alert",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "incident_detected"},
                    {"var": "observed_recent_errors"}
                  ]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "baseline_error_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "incident_detected"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_recent_errors"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "predicted_current_errors"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "should_alert"}]
              }
            }
          }
        ]
      }
    }
  }
}
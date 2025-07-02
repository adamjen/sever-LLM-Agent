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
              "name": "live_metrics",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0},
                  {"literal": 22.0},
                  {"literal": 25.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "baseline_confidence",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "beta",
                  "params": [
                    {"literal": 8.0},
                    {"literal": 2.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "incident_probability",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "beta",
                  "params": [
                    {"literal": 1.0},
                    {"literal": 9.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_alert_triggered",
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
              "name": "current_metric",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "live_metrics"},
                  "index": {"literal": 4}
                }
              }
            }
          },
          {
            "let": {
              "name": "alert_strength",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "is_alert_triggered"},
                    {"var": "current_metric"}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "uncertainty_factor",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "sub",
                  "args": [
                    {"literal": 1.0},
                    {"var": "baseline_confidence"}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "final_alert_score",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "alert_strength"},
                    {"var": "baseline_confidence"}
                  ]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "current_metric"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_alert_triggered"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "alert_strength"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "uncertainty_factor"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "final_alert_score"}]
              }
            }
          }
        ]
      }
    }
  }
}
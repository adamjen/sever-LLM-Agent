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
              "name": "alert_threshold_low",
              "type": "f64",
              "value": {"literal": 5.0}
            }
          },
          {
            "let": {
              "name": "alert_threshold_high", 
              "type": "f64",
              "value": {"literal": 15.0}
            }
          },
          {
            "let": {
              "name": "baseline_error_rate_prior",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 2.5},
                    {"literal": 1.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "incident_severity_prior",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 10.0},
                    {"literal": 2.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "incident_probability_estimate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "beta",
                  "params": [
                    {"literal": 2.0},
                    {"literal": 18.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_critical_incident",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "incident_probability_estimate"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "current_metric_value",
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
              "name": "expected_rate_if_normal",
              "type": "f64",
              "value": {"var": "baseline_error_rate_prior"}
            }
          },
          {
            "let": {
              "name": "expected_rate_if_incident",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "baseline_error_rate_prior"},
                    {"var": "incident_severity_prior"}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "alert_confidence",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "is_critical_incident"},
                    {
                      "op": {
                        "kind": "div",
                        "args": [
                          {"var": "current_metric_value"},
                          {"var": "alert_threshold_high"}
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
              "name": "uncertainty_score",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "sub",
                  "args": [
                    {"literal": 1.0},
                    {"var": "incident_probability_estimate"}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "alert_priority_score",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "alert_confidence"},
                    {
                      "op": {
                        "kind": "sub",
                        "args": [
                          {"literal": 1.0},
                          {"var": "uncertainty_score"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "current_metric_value"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_critical_incident"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "alert_confidence"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "uncertainty_score"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "alert_priority_score"}]
              }
            }
          }
        ]
      }
    }
  }
}
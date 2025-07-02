// Bayesian Changepoint Detection for Observability Metrics
// Detects anomalies in time series data like response times, error rates, etc.

{
  "program": {
    "entry": "detect_anomalies",
    "functions": {
      "detect_anomalies": {
        "args": [
          {"name": "metrics", "type": "array_f64"},
          {"name": "timestamps", "type": "array_f64"},
          {"name": "baseline_window", "type": "i32"}
        ],
        "return": "void",
        "body": [
          {
            "comment": "Bayesian changepoint model for detecting metric anomalies"
          },
          {
            "let": {
              "name": "n_points",
              "value": {"call": {"function": "array_length", "args": [{"var": "metrics"}]}}
            }
          },
          {
            "let": {
              "name": "changepoint_prob",
              "value": {"literal": 0.01}
            }
          },
          {
            "comment": "Prior parameters for normal segments"
          },
          {
            "let": {
              "name": "baseline_mean",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"literal": 0.0},
                    {"literal": 10.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "baseline_precision",
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
            "comment": "Anomaly segment parameters"
          },
          {
            "let": {
              "name": "anomaly_scale",
              "value": {
                "sample": {
                  "distribution": "lognormal",
                  "params": [
                    {"literal": 0.0},
                    {"literal": 0.5}
                  ]
                }
              }
            }
          },
          {
            "comment": "Model each time point"
          },
          {
            "for": {
              "var": "t",
              "start": {"literal": 1},
              "end": {"var": "n_points"},
              "body": [
                {
                  "let": {
                    "name": "is_changepoint",
                    "value": {
                      "sample": {
                        "distribution": "bernoulli",
                        "params": [{"var": "changepoint_prob"}]
                      }
                    }
                  }
                },
                {
                  "let": {
                    "name": "current_mean",
                    "value": {
                      "if": {
                        "condition": {"var": "is_changepoint"},
                        "then": {
                          "op": {
                            "kind": "multiply",
                            "args": [
                              {"var": "baseline_mean"},
                              {"var": "anomaly_scale"}
                            ]
                          }
                        },
                        "else": {"var": "baseline_mean"}
                      }
                    }
                  }
                },
                {
                  "let": {
                    "name": "observed_value",
                    "value": {
                      "call": {
                        "function": "array_get",
                        "args": [{"var": "metrics"}, {"var": "t"}]
                      }
                    }
                  }
                },
                {
                  "observe": {
                    "distribution": "normal",
                    "params": [
                      {"var": "current_mean"},
                      {"op": {"kind": "sqrt", "args": [{"op": {"kind": "divide", "args": [{"literal": 1.0}, {"var": "baseline_precision"}]}}]}}
                    ],
                    "value": {"var": "observed_value"}
                  }
                }
              ]
            }
          },
          {
            "comment": "Run MCMC inference"
          },
          {
            "let": {
              "name": "mcmc_config",
              "value": {
                "struct": {
                  "method": {"literal": "adaptive_metropolis"},
                  "num_samples": {"literal": 2000},
                  "burnin": {"literal": 500},
                  "thin": {"literal": 2}
                }
              }
            }
          },
          {
            "let": {
              "name": "posterior_samples",
              "value": {
                "call": {
                  "function": "run_mcmc_inference",
                  "args": [{"var": "mcmc_config"}]
                }
              }
            }
          },
          {
            "comment": "Compute anomaly probabilities"
          },
          {
            "call": {
              "function": "compute_anomaly_scores",
              "args": [
                {"var": "posterior_samples"},
                {"var": "metrics"},
                {"var": "timestamps"}
              ]
            }
          }
        ]
      },
      
      "compute_anomaly_scores": {
        "args": [
          {"name": "samples", "type": "mcmc_samples"},
          {"name": "metrics", "type": "array_f64"},
          {"name": "timestamps", "type": "array_f64"}
        ],
        "return": "array_f64",
        "body": [
          {
            "comment": "Compute posterior probability of anomaly at each time point"
          },
          {
            "let": {
              "name": "n_points",
              "value": {"call": {"function": "array_length", "args": [{"var": "metrics"}]}}
            }
          },
          {
            "let": {
              "name": "anomaly_scores",
              "value": {"call": {"function": "array_zeros", "args": [{"var": "n_points"}]}}
            }
          },
          {
            "for": {
              "var": "t",
              "start": {"literal": 0},
              "end": {"var": "n_points"},
              "body": [
                {
                  "let": {
                    "name": "changepoint_count",
                    "value": {"literal": 0}
                  }
                },
                {
                  "for": {
                    "var": "s",
                    "start": {"literal": 0},
                    "end": {"call": {"function": "get_num_samples", "args": [{"var": "samples"}]}},
                    "body": [
                      {
                        "let": {
                          "name": "is_changepoint_sample",
                          "value": {
                            "call": {
                              "function": "get_sample_value",
                              "args": [
                                {"var": "samples"},
                                {"var": "s"},
                                {"op": {"kind": "concat", "args": [{"literal": "is_changepoint_"}, {"var": "t"}]}}
                              ]
                            }
                          }
                        }
                      },
                      {
                        "if": {
                          "condition": {"var": "is_changepoint_sample"},
                          "then": {
                            "assign": {
                              "name": "changepoint_count",
                              "value": {"op": {"kind": "add", "args": [{"var": "changepoint_count"}, {"literal": 1}]}}
                            }
                          }
                        }
                      }
                    ]
                  }
                },
                {
                  "let": {
                    "name": "anomaly_probability",
                    "value": {
                      "op": {
                        "kind": "divide",
                        "args": [
                          {"var": "changepoint_count"},
                          {"call": {"function": "get_num_samples", "args": [{"var": "samples"}]}}
                        ]
                      }
                    }
                  }
                },
                {
                  "call": {
                    "function": "array_set",
                    "args": [
                      {"var": "anomaly_scores"},
                      {"var": "t"},
                      {"var": "anomaly_probability"}
                    ]
                  }
                }
              ]
            }
          },
          {
            "return": {"var": "anomaly_scores"}
          }
        ]
      }
    }
  }
}
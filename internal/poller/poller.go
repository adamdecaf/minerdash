package poller

import (
	"context"
	"log"
	"time"

	"github.com/adamdecaf/hasherdash/internal/models"
	"github.com/adamdecaf/hasherdash/internal/store"
)

// Source collects miner snapshots once.
type Source interface {
	// Collect returns the latest detail for every known miner.
	// Implementations may discover new IPs over time.
	Collect(ctx context.Context) ([]models.Detail, error)
	Name() string
}

// Forgetter can drop discovered IPs that the store has pruned.
type Forgetter interface {
	Forget(ids []string)
}

// Runner periodically polls a Source into a Store.
type Runner struct {
	src      Source
	store    *store.Store
	every    time.Duration
	minerTTL time.Duration
	logger   *log.Logger
}

// NewRunner creates a poll loop.
func NewRunner(src Source, st *store.Store, every, minerTTL time.Duration, logger *log.Logger) *Runner {
	if logger == nil {
		logger = log.Default()
	}
	return &Runner{src: src, store: st, every: every, minerTTL: minerTTL, logger: logger}
}

// Run blocks until ctx is cancelled.
func (r *Runner) Run(ctx context.Context) {
	r.logger.Printf("poller: source=%s interval=%s miner_ttl=%s", r.src.Name(), r.every, ttlLabel(r.minerTTL))
	r.tick(ctx)

	t := time.NewTicker(r.every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.tick(ctx)
		}
	}
}

func (r *Runner) tick(ctx context.Context) {
	r.store.SetPolling(true)
	start := time.Now()
	details, err := r.src.Collect(ctx)
	if err != nil {
		r.logger.Printf("poller: collect error: %v", err)
		r.store.MarkPoll(err)
		for _, d := range details {
			r.store.Upsert(d)
		}
		r.prune()
		return
	}
	for _, d := range details {
		r.store.Upsert(d)
	}
	r.store.MarkPoll(nil)
	r.prune()
	r.logger.Printf("poller: updated %d miners in %s", len(details), time.Since(start).Round(time.Millisecond))
}

func (r *Runner) prune() {
	removed := r.store.Prune(r.minerTTL)
	if len(removed) == 0 {
		return
	}
	r.logger.Printf("poller: pruned %d miners past ttl", len(removed))
	if f, ok := r.src.(Forgetter); ok {
		f.Forget(removed)
	}
}

func ttlLabel(d time.Duration) string {
	if d <= 0 {
		return "forever"
	}
	return d.String()
}

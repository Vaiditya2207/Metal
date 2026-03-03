sed -i '' 's/self.closeUpTo(.head);/if (self.hasOpenElement(.head)) self.closeUpTo(.head);/g' src/dom/builder.zig

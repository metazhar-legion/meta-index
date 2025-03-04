import React from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  CircularProgress,
  Chip
} from '@mui/material';
import { Token } from '../contracts/contractTypes';

interface TokenListProps {
  tokens: Token[];
  isLoading: boolean;
  error: string | null;
}

const TokenList: React.FC<TokenListProps> = ({ tokens, isLoading, error }) => {
  if (isLoading) {
    return (
      <Box display="flex" justifyContent="center" my={4}>
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Box my={2}>
        <Typography color="error">{error}</Typography>
      </Box>
    );
  }

  if (tokens.length === 0) {
    return (
      <Box my={2}>
        <Typography variant="body2" color="text.secondary">
          No tokens in the index yet.
        </Typography>
      </Box>
    );
  }

  // Calculate total weight
  const totalWeight = tokens.reduce((sum, token) => sum + Number(token.weight || 0), 0);

  return (
    <Card variant="outlined" sx={{ mb: 3 }}>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          Index Composition
        </Typography>
        <TableContainer component={Paper} variant="outlined">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Token</TableCell>
                <TableCell>Address</TableCell>
                <TableCell align="right">Weight</TableCell>
                <TableCell align="right">Allocation</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {tokens.map((token) => (
                <TableRow key={token.address}>
                  <TableCell>
                    <Chip label={token.symbol} size="small" />
                  </TableCell>
                  <TableCell>
                    <Typography variant="body2" sx={{ fontSize: '0.75rem' }}>
                      {`${token.address.substring(0, 6)}...${token.address.substring(
                        token.address.length - 4
                      )}`}
                    </Typography>
                  </TableCell>
                  <TableCell align="right">{token.weight}</TableCell>
                  <TableCell align="right">
                    {totalWeight > 0
                      ? `${((Number(token.weight) / totalWeight) * 100).toFixed(2)}%`
                      : '0%'}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </CardContent>
    </Card>
  );
};

export default TokenList;

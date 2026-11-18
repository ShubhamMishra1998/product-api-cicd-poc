package com.example.productapi.repository;

import com.example.productapi.entity.Product;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

@Repository
public class ProductRepository {
    private final ConcurrentHashMap<Long, Product> products = new ConcurrentHashMap<>();

    private final AtomicLong idGenerator = new AtomicLong(0);

    public Product save(Product product) {
        Long id = idGenerator.incrementAndGet();

        Product savedProduct = new Product(
                id,
                product.name(),
                product.description(),
                product.price()
        );

        products.put(id, savedProduct);
        return savedProduct;
    }

    public List<Product> findAll() {
        return List.copyOf(products.values());
    }

    public Optional<Product> findById(Long id) {
        return Optional.ofNullable(products.get(id));
    }

    public boolean deleteById(Long id) {
        return products.remove(id) != null;
    }
}
